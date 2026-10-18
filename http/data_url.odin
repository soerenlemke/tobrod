package http

import "core:encoding/base64"
import "core:strings"

// data: URLs carry their content in the URL itself (RFC 2397):
//
//   data:[<media type>][;base64],<data>
//
// Pages use them for small images, most of all for SVG icons in their CSS
// (data:image/svg+xml;utf8,<svg ...>). Without ;base64 the data is
// percent-encoded text. Nothing is loaded, so they don't go through curl.

is_data_url :: proc(url: string) -> bool {
	return len(url) >= 5 && strings.equal_fold(url[:5], "data:")
}

// The bytes and the media type of a data: URL, allocated with allocator.
decode_data_url :: proc(url: string, allocator := context.allocator) -> (data: []u8, content_type: string, ok: bool) {
	if !is_data_url(url) {
		return
	}
	comma := strings.index_byte(url, ',')
	if comma < 0 {
		return
	}
	header, payload := url[5:comma], url[comma + 1:]
	is_base64 := false
	if strings.has_suffix(strings.to_lower(header, context.temp_allocator), ";base64") {
		is_base64 = true
		header = header[:len(header) - len(";base64")]
	}
	content_type = header if header != "" else "text/plain"

	text := percent_decode(payload, context.temp_allocator)
	if is_base64 {
		// spaces may be in there (line breaks in the CSS)
		compact, _ := strings.remove_all(string(text), " ", context.temp_allocator)
		decoded, err := base64.decode(compact, allocator = allocator)
		if err != nil {
			return nil, "", false
		}
		return decoded, content_type, true
	}
	return clone_bytes(text, allocator), content_type, true
}

// %XX -> the byte; everything else stays.
@(private)
percent_decode :: proc(s: string, allocator := context.allocator) -> []u8 {
	result := make([dynamic]u8, 0, len(s), allocator)
	hex :: proc(c: u8) -> (u8, bool) {
		switch c {
		case '0' ..= '9':
			return c - '0', true
		case 'a' ..= 'f':
			return c - 'a' + 10, true
		case 'A' ..= 'F':
			return c - 'A' + 10, true
		}
		return 0, false
	}
	for i := 0; i < len(s); i += 1 {
		if s[i] == '%' && i + 2 < len(s) {
			hi, ok1 := hex(s[i + 1])
			lo, ok2 := hex(s[i + 2])
			if ok1 && ok2 {
				append(&result, hi << 4 | lo)
				i += 2
				continue
			}
		}
		append(&result, s[i])
	}
	return result[:]
}

@(private)
clone_bytes :: proc(b: []u8, allocator := context.allocator) -> []u8 {
	result := make([]u8, len(b), allocator)
	copy(result, b)
	return result
}
