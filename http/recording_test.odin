package http

import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"
import "core:time"

@(test)
test_record_and_replay :: proc(t: ^testing.T) {
	dir := fmt.aprintf("%s/tobrod-recording-test-%d", os.temp_directory(context.temp_allocator) or_else ".", time.now()._nsec)
	defer delete(dir)
	testing.expect(t, set_recording(.Record, dir) == nil, "creates the directory")
	defer {
		set_recording(.Off, "")
		os.remove_all(dir)
	}

	// what get saves after a real request (with a redirect)
	record_response("https://example.com/a", {
		url    = "https://example.com/b",
		header = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\r\n",
		body   = "<p>hello\nworld</p>",
	})

	set_recording(.Replay, dir)
	// a client without curl: replaying only fills the builders
	c: Client
	strings.builder_init(&c.header_builder)
	strings.builder_init(&c.body_builder)
	strings.builder_init(&c.url_builder)
	defer {
		strings.builder_destroy(&c.header_builder)
		strings.builder_destroy(&c.body_builder)
		strings.builder_destroy(&c.url_builder)
	}

	response, err := replay_response(&c, "https://example.com/a")
	testing.expect(t, err == nil, "recorded")
	testing.expect_value(t, response.url, "https://example.com/b")
	content_type, _ := header_value(response.header, "content-type")
	testing.expect_value(t, content_type, "text/html")
	testing.expect_value(t, response.body, "<p>hello\nworld</p>")

	_, missing := replay_response(&c, "https://example.com/other")
	testing.expect(t, missing != nil, "not recorded: an error")
}
