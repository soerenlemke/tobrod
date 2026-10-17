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

// Completes what was typed into the address bar to a URL, like a browser:
// "example.com/a" becomes "https://example.com/a". Local addresses
// (localhost, IP addresses) get "http://", because local test servers
// rarely speak TLS. Input with a scheme ("http://", "file:", ...) is kept.
// The result is allocated with the given allocator.
complete_url :: proc(input: string, allocator := context.allocator) -> string {
	input := strings.trim_space(input)
	if input == "" || has_scheme(input) {
		return strings.clone(input, allocator)
	}
	scheme := "http://" if is_local_host(host_of(input)) else "https://"
	return strings.concatenate({scheme, input}, allocator)
}

// "http://..." or "mailto:...": letters, digits, + - . before the first ':',
// starting with a letter. "localhost:8080" also looks like that, so a ':'
// followed by a digit is treated as a port, not a scheme.
@(private)
has_scheme :: proc(input: string) -> bool {
	colon := strings.index_byte(input, ':')
	if colon <= 0 {
		return false
	}
	if strings.has_prefix(input[colon:], "://") {
		return true
	}
	if colon + 1 < len(input) && is_digit(input[colon + 1]) {
		return false // host:port
	}
	for c, i in transmute([]u8)input[:colon] {
		ok := is_letter(c) || (i > 0 && (is_digit(c) || c == '+' || c == '-' || c == '.'))
		if !ok {
			return false
		}
	}
	return true
}

// The host of an address without scheme: "host:port/path?q#f" → "host".
@(private)
host_of :: proc(input: string) -> string {
	host := input
	if end := strings.index_any(host, "/?#"); end >= 0 {
		host = host[:end]
	}
	if strings.has_prefix(host, "[") {
		// IPv6: "[::1]:8080"
		if end := strings.index_byte(host, ']'); end >= 0 {
			return host[:end + 1]
		}
		return host
	}
	if colon := strings.index_byte(host, ':'); colon >= 0 {
		host = host[:colon]
	}
	return host
}

@(private)
is_local_host :: proc(host: string) -> bool {
	host := strings.to_lower(host, context.temp_allocator)
	if host == "localhost" || strings.has_suffix(host, ".localhost") || strings.has_prefix(host, "[") {
		return true
	}
	// an IPv4 address: only digits and dots
	if host == "" {
		return false
	}
	for c in transmute([]u8)host {
		if !is_digit(c) && c != '.' {
			return false
		}
	}
	return true
}

@(private)
is_digit :: proc(c: u8) -> bool {
	return c >= '0' && c <= '9'
}

@(private)
is_letter :: proc(c: u8) -> bool {
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}
