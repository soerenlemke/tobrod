package loader

import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:slice"
import "core:strings"
import "core:sync"
import "core:thread"
import "../dom"
import "../http"

// Loads pages and their resources (images) on a worker thread, so the ui
// keeps running while we wait for the network. The ui thread hands in
// requests with load() / load_resource() and picks up the results with
// poll() once per frame.
//
// Pages come first: there is at most one waiting page request, and a new one
// replaces it, cancels what is in progress and drops all queued resources
// (they belonged to the old page). Resources wait in a queue and are loaded
// one after another.
//
// Thread safety:
// - the worker owns its own http.Client (a curl handle must not be used by
//   two threads at the same time)
// - pending, resources, results and quit are shared and only touched with
//   the mutex held
// - abort is read by curl's progress callback without the mutex, so it is
//   only accessed atomically

Request_Id :: u64

Request_Kind :: enum {
	Page,     // downloaded and parsed into a document
	Resource, // downloaded only, e.g. an image
}

// A finished request. Owned by the receiver: free it with result_destroy.
Result :: struct {
	id:           Request_Id,
	kind:         Request_Kind,
	url:          string,        // where we ended up after redirects
	document:     ^dom.Document, // pages only, nil on error
	data:         []u8,          // resources only: the raw bytes
	content_type: string,        // resources only, e.g. "image/png"
	error:        string,        // "" on success
}

Loader :: struct {
	allocator: mem.Allocator, // for everything that crosses threads
	client:    http.Client,   // used by the worker only
	worker:    ^thread.Thread,
	next_id:   Request_Id,    // ui thread only

	mutex:     sync.Mutex,
	cond:      sync.Cond,     // signals the worker: new request or quit
	pending:   Maybe(Request),    // the page to load next
	resources: [dynamic]Request,  // queued resources, loaded after the page
	results:   [dynamic]Result,
	quit:      bool,

	abort:     bool,          // atomic; cancels the request in progress
}

@(private)
Request :: struct {
	id:   Request_Id,
	kind: Request_Kind,
	url:  string,
}

init :: proc(l: ^Loader, allocator := context.allocator) -> Maybe(http.Http_Error) {
	l.allocator = allocator
	l.results.allocator = allocator
	l.resources.allocator = allocator
	l.next_id = 1

	client, err := http.init()
	if e, ok := err.?; ok {
		return e
	}
	l.client = client
	l.worker = thread.create_and_start_with_data(l, worker_proc)
	return nil
}

// Stops the worker (cancelling what it is doing) and frees everything.
destroy :: proc(l: ^Loader) {
	sync.mutex_lock(&l.mutex)
	l.quit = true
	sync.atomic_store(&l.abort, true)
	sync.cond_signal(&l.cond)
	sync.mutex_unlock(&l.mutex)

	thread.join(l.worker)
	thread.destroy(l.worker)

	if request, ok := l.pending.?; ok {
		delete(request.url, l.allocator)
	}
	drop_resources(l)
	delete(l.resources)
	for &result in l.results {
		result_destroy(&result)
	}
	delete(l.results)
	http.destroy(&l.client)
}

// Starts loading the page at url. Replaces a page request that is still
// waiting, drops all queued resources and cancels what is in progress, so only
// the newest navigation is worked on.
load :: proc(l: ^Loader, url: string) -> Request_Id {
	id := l.next_id
	l.next_id += 1

	sync.mutex_lock(&l.mutex)
	defer sync.mutex_unlock(&l.mutex)

	if old, ok := l.pending.?; ok {
		delete(old.url, l.allocator)
	}
	l.pending = Request{id = id, kind = .Page, url = strings.clone(url, l.allocator)}
	drop_resources(l)
	sync.atomic_store(&l.abort, true)
	sync.cond_signal(&l.cond)
	return id
}

// Queues a resource (e.g. an image) of the current page. Does not cancel anything.
load_resource :: proc(l: ^Loader, url: string) -> Request_Id {
	id := l.next_id
	l.next_id += 1

	sync.mutex_lock(&l.mutex)
	defer sync.mutex_unlock(&l.mutex)

	append(&l.resources, Request{id = id, kind = .Resource, url = strings.clone(url, l.allocator)})
	sync.cond_signal(&l.cond)
	return id
}

// Drops all waiting requests and cancels the one in progress (stop button).
cancel :: proc(l: ^Loader) {
	sync.mutex_lock(&l.mutex)
	defer sync.mutex_unlock(&l.mutex)

	if old, ok := l.pending.?; ok {
		delete(old.url, l.allocator)
		l.pending = nil
	}
	drop_resources(l)
	sync.atomic_store(&l.abort, true)
}

// Call with the mutex held.
@(private)
drop_resources :: proc(l: ^Loader) {
	for request in l.resources {
		delete(request.url, l.allocator)
	}
	clear(&l.resources)
}

// Takes the next finished request, if there is one. Never blocks.
poll :: proc(l: ^Loader) -> (result: Result, ok: bool) {
	sync.mutex_lock(&l.mutex)
	defer sync.mutex_unlock(&l.mutex)

	if len(l.results) == 0 {
		return {}, false
	}
	return pop_front(&l.results), true
}

result_destroy :: proc(r: ^Result, allocator := context.allocator) {
	delete(r.url, allocator)
	delete(r.error, allocator)
	delete(r.data, allocator)
	delete(r.content_type, allocator)
	if r.document != nil {
		dom.destroy(r.document)
	}
	r^ = {}
}

@(private)
worker_proc :: proc(data: rawptr) {
	l := cast(^Loader)data
	// a fresh context: the worker gets its own temp allocator, but shares the
	// heap allocator with the ui thread, because results are freed there
	context = runtime.default_context()
	context.allocator = l.allocator

	for {
		sync.mutex_lock(&l.mutex)
		for l.pending == nil && len(l.resources) == 0 && !l.quit {
			// releases the mutex while sleeping, re-locks before returning
			sync.cond_wait(&l.cond, &l.mutex)
		}
		if l.quit {
			sync.mutex_unlock(&l.mutex)
			return
		}
		// pages first, then resources in the order they were requested
		request: Request
		if page, ok := l.pending.?; ok {
			request = page
			l.pending = nil
		} else {
			request = pop_front(&l.resources)
		}
		// reset under the mutex, so a load() right after this aborts the new request
		sync.atomic_store(&l.abort, false)
		sync.mutex_unlock(&l.mutex)

		result, finished := fetch(l, request)
		delete(request.url)

		if finished {
			sync.mutex_lock(&l.mutex)
			append(&l.results, result)
			sync.mutex_unlock(&l.mutex)
		}
		free_all(context.temp_allocator)
	}
}

// Downloads one page (and parses it) or resource. finished is false if it
// was cancelled: nobody is waiting for that result anymore.
@(private)
fetch :: proc(l: ^Loader, request: Request) -> (result: Result, finished: bool) {
	result.id = request.id
	result.kind = request.kind

	response, err := http.get(&l.client, request.url, &l.abort)
	if e, failed := err.?; failed {
		if e.code == .E_ABORTED_BY_CALLBACK {
			return {}, false
		}
		result.url = strings.clone(request.url)
		result.error = fmt.aprintf("Could not load %s: %s", request.url, e.message)
		return result, true
	}
	result.url = strings.clone(response.url if response.url != "" else request.url)

	content_type, _ := http.header_value(response.header, "Content-Type")
	if request.kind == .Resource {
		// the response buffers belong to the http client: copy them out
		result.data = slice.clone(transmute([]u8)response.body)
		result.content_type = strings.clone(content_type)
		return result, true
	}

	parse_err: Maybe(dom.Parse_Error)
	if strings.has_prefix(content_type, "text/html") {
		result.document, parse_err = dom.parse(response.body)
	} else {
		result.document, parse_err = dom.from_plain_text(response.body)
	}
	if e, failed := parse_err.?; failed {
		result.error = strings.clone(e.message)
	}
	return result, true
}
