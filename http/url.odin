package http

import "core:strings"
import curl "../vendor/curl"

// Resolves a link against the URL of the page it is on, like a browser does
// for <a href>: "b.html", "../x", "/root", "?q=1", "//host/path" or a full URL.
// Uses curl's URL API, which implements the rules of RFC 3986.
// The result is allocated with the given allocator.
resolve_url :: proc(base, reference: string, allocator := context.allocator) -> (url: string, ok: bool) {
	handle := curl.url()
	if handle == nil {
		return "", false
	}
	defer curl.url_cleanup(handle)

	base_c := strings.clone_to_cstring(base, context.temp_allocator)
	reference_c := strings.clone_to_cstring(strings.trim_space(reference), context.temp_allocator)

	if curl.url_set(handle, .URL, base_c, {}) != .E_OK {
		return "", false
	}
	// with a URL already set, curl resolves a relative one against it
	if curl.url_set(handle, .URL, reference_c, {}) != .E_OK {
		return "", false
	}

	result: cstring
	if curl.url_get(handle, .URL, &result, {}) != .E_OK {
		return "", false
	}
	defer curl.free(rawptr(result))
	return strings.clone(string(result), allocator), true
}

// Only http(s) can be loaded; mailto:, javascript: etc. are ignored.
is_loadable_url :: proc(url: string) -> bool {
	return strings.has_prefix(url, "http://") || strings.has_prefix(url, "https://")
}
