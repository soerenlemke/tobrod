package http

import "core:testing"

@(test)
test_header_value :: proc(t: ^testing.T) {
	raw := "HTTP/1.1 301 Moved\r\nLocation: /new\r\nContent-Type: text/plain\r\n\r\n" +
		"HTTP/1.1 200 OK\r\ncontent-type:  text/html; charset=utf-8 \r\n\r\n"

	value, ok := header_value(raw, "Content-Type")
	testing.expect(t, ok, "expected content-type")
	testing.expect_value(t, value, "text/html; charset=utf-8")

	_, missing := header_value(raw, "X-Missing")
	testing.expect(t, !missing, "expected missing header")
}
