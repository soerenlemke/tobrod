package loader

import "core:fmt"
import "core:net"
import "core:strings"
import "core:sync"
import "core:testing"
import "core:thread"
import "core:time"
import "../dom"
import curl "../vendor/curl"

// A tiny HTTP server on a random local port, so the tests need no internet
// and always get the same answers. One thread per connection, so a slow
// response doesn't block the next request.
@(private = "file")
Test_Server :: struct {
	socket:   net.TCP_Socket,
	base_url: string,
	acceptor: ^thread.Thread,
	mutex:    sync.Mutex,
	handlers: [dynamic]^thread.Thread,
}

SLOW_RESPONSE :: 5 * time.Second

@(private = "file")
server_start :: proc(t: ^testing.T, s: ^Test_Server) {
	socket, err := net.listen_tcp({address = net.IP4_Loopback, port = 0})
	if err != nil {
		testing.fail_now(t, "could not start test server")
	}
	endpoint, _ := net.bound_endpoint(socket)
	s.socket = socket
	s.base_url = fmt.aprintf("http://127.0.0.1:%d", endpoint.port)
	s.acceptor = thread.create_and_start_with_data(s, accept_loop, context)
}

@(private = "file")
server_stop :: proc(s: ^Test_Server) {
	net.close(s.socket) // makes accept fail, which ends the accept loop
	thread.join(s.acceptor)
	thread.destroy(s.acceptor)
	for h in s.handlers {
		thread.join(h)
		thread.destroy(h)
	}
	delete(s.handlers)
	delete(s.base_url)
}

@(private = "file")
accept_loop :: proc(data: rawptr) {
	s := cast(^Test_Server)data
	for {
		client, _, err := net.accept_tcp(s.socket)
		if err != nil {
			return
		}
		h := thread.create_and_start_with_poly_data(client, handle_connection, context)
		sync.mutex_lock(&s.mutex)
		append(&s.handlers, h)
		sync.mutex_unlock(&s.mutex)
	}
}

@(private = "file")
handle_connection :: proc(client: net.TCP_Socket) {
	defer net.close(client)

	buf: [4096]u8
	n, err := net.recv_tcp(client, buf[:])
	if err != nil || n == 0 {
		return
	}
	// "GET /path HTTP/1.1" -> "/path"
	request := string(buf[:n])
	path := ""
	if parts := strings.split(request, " ", context.temp_allocator); len(parts) >= 2 {
		path = parts[1]
	}

	switch path {
	case "/page.html":
		respond(client, "200 OK", "text/html", "<html><body><p>Hello <b>page</b></p></body></html>")
	case "/text":
		respond(client, "200 OK", "text/plain", "just text")
	case "/redirect":
		net.send_tcp(client, transmute([]u8)string("HTTP/1.1 302 Found\r\nLocation: /page.html\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"))
	case "/image.bin":
		respond(client, "200 OK", "image/png", "PNG fake bytes")
	case "/slow":
		time.sleep(SLOW_RESPONSE)
		respond(client, "200 OK", "text/plain", "slow")
	case:
		respond(client, "404 Not Found", "text/plain", "not found")
	}
}

@(private = "file")
respond :: proc(client: net.TCP_Socket, status, content_type, body: string) {
	response := fmt.tprintf(
		"HTTP/1.1 %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s",
		status, content_type, len(body), body,
	)
	net.send_tcp(client, transmute([]u8)response)
}

// Polls until a result arrives or the timeout is over.
@(private = "file")
wait_for_result :: proc(l: ^Loader, timeout: time.Duration) -> (result: Result, ok: bool) {
	deadline := time.tick_now()
	for time.tick_since(deadline) < timeout {
		if result, ok = poll(l); ok {
			return
		}
		time.sleep(10 * time.Millisecond)
	}
	return {}, false
}

@(private = "file")
setup :: proc(t: ^testing.T, s: ^Test_Server, l: ^Loader) {
	server_start(t, s)
	if err, failed := init(l).?; failed {
		testing.fail_now(t, err.message)
	}
}

@(test)
test_load_html :: proc(t: ^testing.T) {
	s: Test_Server
	l: Loader
	setup(t, &s, &l)
	defer server_stop(&s)
	defer destroy(&l)

	url := fmt.tprintf("%s/page.html", s.base_url)
	id := load(&l, url)
	result, ok := wait_for_result(&l, 5 * time.Second)
	testing.expect(t, ok, "expected a result")
	defer result_destroy(&result)

	testing.expect_value(t, result.id, id)
	testing.expect_value(t, result.error, "")
	testing.expect_value(t, result.url, url)
	testing.expect(t, result.document != nil, "expected a parsed document")
	if result.document != nil {
		tree := dom.tree_to_string(result.document.root, context.temp_allocator)
		testing.expect(t, strings.contains(tree, `"Hello "`), "expected the page text in the DOM")
	}
}

@(test)
test_redirect_and_plain_text :: proc(t: ^testing.T) {
	s: Test_Server
	l: Loader
	setup(t, &s, &l)
	defer server_stop(&s)
	defer destroy(&l)

	load(&l, fmt.tprintf("%s/redirect", s.base_url))
	result, ok := wait_for_result(&l, 5 * time.Second)
	testing.expect(t, ok, "expected a result")
	testing.expect_value(t, result.url, fmt.tprintf("%s/page.html", s.base_url))
	result_destroy(&result)

	load(&l, fmt.tprintf("%s/text", s.base_url))
	result, ok = wait_for_result(&l, 5 * time.Second)
	testing.expect(t, ok, "expected a result")
	defer result_destroy(&result)
	if result.document != nil {
		tree := dom.tree_to_string(result.document.root, context.temp_allocator)
		testing.expect(t, strings.contains(tree, "<pre>"), "plain text is wrapped in <pre>")
	}
}

@(test)
test_connection_error :: proc(t: ^testing.T) {
	s: Test_Server
	l: Loader
	setup(t, &s, &l)
	defer destroy(&l)
	// stop the server right away: its port refuses connections now
	url := fmt.tprintf("%s/page.html", s.base_url)
	server_stop(&s)

	load(&l, url)
	result, ok := wait_for_result(&l, 10 * time.Second)
	testing.expect(t, ok, "expected a result")
	defer result_destroy(&result)
	testing.expect(t, result.error != "", "expected an error message")
	testing.expect(t, result.document == nil, "expected no document")
}

@(test)
test_newer_request_cancels_older :: proc(t: ^testing.T) {
	s: Test_Server
	l: Loader
	setup(t, &s, &l)
	defer server_stop(&s)
	defer destroy(&l)

	load(&l, fmt.tprintf("%s/slow", s.base_url))
	time.sleep(100 * time.Millisecond) // let the worker start on it
	start := time.tick_now()
	id := load(&l, fmt.tprintf("%s/page.html", s.base_url))

	// the slow page is aborted, so the new one arrives long before it would finish
	result, ok := wait_for_result(&l, 5 * time.Second)
	testing.expect(t, ok, "expected a result")
	defer result_destroy(&result)
	testing.expect_value(t, result.id, id)
	testing.expect(t, time.tick_since(start) < SLOW_RESPONSE - time.Second, "expected the slow request to be aborted")

	_, more := poll(&l)
	testing.expect(t, !more, "the cancelled request must not deliver a result")
}

@(test)
test_cancel :: proc(t: ^testing.T) {
	s: Test_Server
	l: Loader
	setup(t, &s, &l)
	defer server_stop(&s)
	defer destroy(&l)

	load(&l, fmt.tprintf("%s/slow", s.base_url))
	time.sleep(100 * time.Millisecond)
	cancel(&l)

	_, ok := wait_for_result(&l, 3 * time.Second)
	testing.expect(t, !ok, "a cancelled request delivers no result")
}

@(test)
test_destroy_while_loading :: proc(t: ^testing.T) {
	s: Test_Server
	l: Loader
	setup(t, &s, &l)
	defer server_stop(&s)

	// closing the browser during a slow load must not hang until it finishes
	load(&l, fmt.tprintf("%s/slow", s.base_url))
	time.sleep(100 * time.Millisecond)
	start := time.tick_now()
	destroy(&l)
	testing.expect(t, time.tick_since(start) < 3 * time.Second, "destroy should abort the transfer")
}

// curl_global_init must run once before threads use curl; the test runner has
// no main, so do it for the whole package here. @(init) procs run before any
// context exists, so this one is "contextless" and calls curl directly.
@(init)
init_curl :: proc "contextless" () {
	curl.global_init(curl.GLOBAL_DEFAULT)
}

@(test)
test_resources :: proc(t: ^testing.T) {
	s: Test_Server
	l: Loader
	setup(t, &s, &l)
	defer server_stop(&s)
	defer destroy(&l)

	a := load_resource(&l, fmt.tprintf("%s/image.bin", s.base_url))
	b := load_resource(&l, fmt.tprintf("%s/text", s.base_url))

	// both arrive, in order, as raw bytes with their content type
	first, ok := wait_for_result(&l, 5 * time.Second)
	testing.expect(t, ok, "expected the first resource")
	defer result_destroy(&first)
	testing.expect_value(t, first.id, a)
	testing.expect_value(t, first.kind, Request_Kind.Resource)
	testing.expect_value(t, string(first.data), "PNG fake bytes")
	testing.expect_value(t, first.content_type, "image/png")
	testing.expect(t, first.document == nil, "resources are not parsed")

	second, ok2 := wait_for_result(&l, 5 * time.Second)
	testing.expect(t, ok2, "expected the second resource")
	defer result_destroy(&second)
	testing.expect_value(t, second.id, b)
}

@(test)
test_new_page_drops_queued_resources :: proc(t: ^testing.T) {
	s: Test_Server
	l: Loader
	setup(t, &s, &l)
	defer server_stop(&s)
	defer destroy(&l)

	// the slow resource blocks the worker, the second one waits in the queue
	load_resource(&l, fmt.tprintf("%s/slow", s.base_url))
	time.sleep(100 * time.Millisecond)
	load_resource(&l, fmt.tprintf("%s/image.bin", s.base_url))
	page := load(&l, fmt.tprintf("%s/page.html", s.base_url))

	// only the page arrives: the slow resource is aborted, the queued one dropped
	result, ok := wait_for_result(&l, 5 * time.Second)
	testing.expect(t, ok, "expected the page")
	defer result_destroy(&result)
	testing.expect_value(t, result.id, page)
	testing.expect_value(t, result.kind, Request_Kind.Page)

	_, more := wait_for_result(&l, 500 * time.Millisecond)
	testing.expect(t, !more, "the old resources must not arrive")
}
