package http

import "core:testing"

@(test)
test_resolve_url :: proc(t: ^testing.T) {
	base := "http://example.com/docs/guide/page.html?x=1#top"
	cases := []struct {
		reference: string,
		expected:  string,
	} {
		{"other.html", "http://example.com/docs/guide/other.html"},
		{"../index.html", "http://example.com/docs/index.html"},
		{"/root.txt", "http://example.com/root.txt"},
		{"?q=2", "http://example.com/docs/guide/page.html?q=2"},
		{"#section", "http://example.com/docs/guide/page.html?x=1#section"},
		{"//cdn.example.org/a.js", "http://cdn.example.org/a.js"},
		{"https://other.org/", "https://other.org/"},
		{"  spaced.html  ", "http://example.com/docs/guide/spaced.html"},
	}
	for c in cases {
		url, ok := resolve_url(base, c.reference)
		defer delete(url)
		testing.expectf(t, ok && url == c.expected, "%q: got %q (%v), want %q", c.reference, url, ok, c.expected)
	}
}

@(test)
test_is_loadable_url :: proc(t: ^testing.T) {
	testing.expect(t, is_loadable_url("https://example.com/"))
	testing.expect(t, is_loadable_url("http://127.0.0.1:8765/a"))
	testing.expect(t, !is_loadable_url("mailto:someone@example.com"))
	testing.expect(t, !is_loadable_url("javascript:void(0)"))
}

@(test)
test_complete_url :: proc(t: ^testing.T) {
	cases := []struct {
		input:    string,
		expected: string,
	} {
		{"example.com", "https://example.com"},
		{"  de.wikipedia.org/wiki/Odin  ", "https://de.wikipedia.org/wiki/Odin"},
		{"example.com:8443/a?b#c", "https://example.com:8443/a?b#c"},
		{"localhost:8765/flex.html", "http://localhost:8765/flex.html"},
		{"127.0.0.1:8765", "http://127.0.0.1:8765"},
		{"[::1]:8080/", "http://[::1]:8080/"},
		{"app.localhost", "http://app.localhost"},
		{"http://example.com/", "http://example.com/"},
		{"HTTPS://Example.com", "HTTPS://Example.com"},
		{"mailto:someone@example.com", "mailto:someone@example.com"},
		{"", ""},
	}
	for c in cases {
		url := complete_url(c.input)
		defer delete(url)
		testing.expectf(t, url == c.expected, "%q: got %q, want %q", c.input, url, c.expected)
	}
}

@(test)
test_data_url :: proc(t: ^testing.T) {
	data, content_type, ok := decode_data_url(`data:image/svg+xml;utf8,<svg fill="%23000"/>`, context.temp_allocator)
	testing.expect(t, ok, "percent-encoded")
	testing.expect_value(t, content_type, "image/svg+xml;utf8")
	testing.expect_value(t, string(data), `<svg fill="#000"/>`)

	data, content_type, ok = decode_data_url("data:image/png;base64,aGVs bG8=", context.temp_allocator)
	testing.expect(t, ok, "base64")
	testing.expect_value(t, content_type, "image/png")
	testing.expect_value(t, string(data), "hello")

	_, _, ok = decode_data_url("https://example.com/a.png", context.temp_allocator)
	testing.expect(t, !ok, "not a data URL")
}
