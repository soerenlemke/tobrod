package http

import "base:runtime"
import "core:c"
import "core:strings"
import "core:sync"
import "../vendor/curl"

STANDARD_READ_TIMEOUT :: 30
MAX_REDIRECTS :: 10
// Sent with every request. Some sites (e.g. Wikipedia) reject requests
// without one; a name and a link to the project is the polite thing to send.
USER_AGENT :: "tobrod/0.1 (toy browser; +https://github.com/soerenlemke/tobrod)"

Http_Error :: struct {
	code:    curl.code,
	message: string,
}

Http_Response :: struct {
	url:    string, // where we ended up after redirects; the base for relative links
	header: string,
	body:   string,
}

Client :: struct {
	handle:         ^curl.CURL,
	header_builder: strings.Builder,
	body_builder:   strings.Builder,
}

// Call once at program start, before any thread uses curl: curl's global
// setup is not thread-safe, so it must not happen lazily inside a thread.
global_init :: proc() -> Maybe(Http_Error) {
	if code := curl.global_init(curl.GLOBAL_DEFAULT); code != .E_OK {
		return Http_Error{code = code, message = string(curl.easy_strerror(code))}
	}
	return nil
}

// Call once at program end, after all clients are destroyed.
global_cleanup :: proc() {
	curl.global_cleanup()
}

// A client may be used by one thread at a time; give every thread its own.
init :: proc() -> (Client, Maybe(Http_Error)) {
	c: Client
	c.handle = curl.easy_init()
	if c.handle == nil {
		return {}, Http_Error{code = .E_FAILED_INIT, message = "curl_easy_init failed"}
	}

	if _, err := strings.builder_init(&c.header_builder); err != .None {
		curl.easy_cleanup(c.handle)
		return {}, Http_Error{code = .E_OUT_OF_MEMORY, message = "out of memory"}
	}
	if _, err := strings.builder_init(&c.body_builder); err != .None {
		strings.builder_destroy(&c.header_builder)
		curl.easy_cleanup(c.handle)
		return {}, Http_Error{code = .E_OUT_OF_MEMORY, message = "out of memory"}
	}

	return c, nil
}

destroy :: proc(c: ^Client) {
	curl.easy_cleanup(c.handle)
	strings.builder_destroy(&c.header_builder)
	strings.builder_destroy(&c.body_builder)
}

// Blocking GET. If abort is given, another thread can set it (atomically) to
// stop the transfer; get then returns an error with code .E_ABORTED_BY_CALLBACK.
get :: proc(c: ^Client, url: string, abort: ^bool = nil) -> (Http_Response, Maybe(Http_Error)) {
	strings.builder_reset(&c.header_builder)
	strings.builder_reset(&c.body_builder)

	url_c := strings.clone_to_cstring(url)
	defer delete(url_c)

	curl.easy_setopt(c.handle, .URL, url_c)
	curl.easy_setopt(c.handle, .HEADERFUNCTION, write_callback)
	curl.easy_setopt(c.handle, .HEADERDATA, &c.header_builder) // header
	curl.easy_setopt(c.handle, .WRITEFUNCTION, write_callback)
	curl.easy_setopt(c.handle, .WRITEDATA, &c.body_builder) // body
	curl.easy_setopt(c.handle, .TIMEOUT, STANDARD_READ_TIMEOUT)
	curl.easy_setopt(c.handle, .FOLLOWLOCATION, 1)
	curl.easy_setopt(c.handle, .MAXREDIRS, MAX_REDIRECTS)
	curl.easy_setopt(c.handle, .USERAGENT, cstring(USER_AGENT))

	// curl calls the progress callback regularly (at least once a second, even
	// while waiting), which is our chance to cancel
	if abort != nil {
		curl.easy_setopt(c.handle, .NOPROGRESS, 0)
		curl.easy_setopt(c.handle, .XFERINFOFUNCTION, abort_callback)
		curl.easy_setopt(c.handle, .XFERINFODATA, abort)
	} else {
		curl.easy_setopt(c.handle, .NOPROGRESS, 1)
	}

	response_code := curl.easy_perform(c.handle)
	if response_code != .E_OK {
		return {}, Http_Error{code = response_code, message = string(curl.easy_strerror(response_code))}
	}

	// owned by curl, valid until the next request on this handle
	effective_url: cstring
	curl.easy_getinfo(c.handle, .EFFECTIVE_URL, &effective_url)

	return {
			url = string(effective_url),
			header = strings.to_string(c.header_builder),
			body = strings.to_string(c.body_builder),
		},
		nil
}

// Returning non-zero makes curl stop the transfer.
@(private)
abort_callback :: proc "c" (clientp: rawptr, dltotal, dlnow, ultotal, ulnow: curl.off_t) -> c.int {
	abort := cast(^bool)clientp
	return 1 if sync.atomic_load(abort) else 0
}

write_callback :: proc "c" (ptr: rawptr, size, nmemb: uint, userdata: rawptr) -> uint {
	context = runtime.default_context()

	builder := cast(^strings.Builder)userdata
	chunk := string(([^]u8)(ptr)[:size * nmemb])
	strings.write_string(builder, chunk)

	return size * nmemb
}
