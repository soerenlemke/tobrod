package http

import "core:strings"

// Looks up a header in the raw header text of a response. Names are case-insensitive.
// With redirects the raw text contains the headers of every response in order,
// so the last match wins.
header_value :: proc(raw_header: string, name: string) -> (value: string, ok: bool) {
	rest := raw_header
	for line in strings.split_lines_iterator(&rest) {
		colon := strings.index_byte(line, ':')
		if colon < 0 {
			continue // status line or empty line
		}
		if strings.equal_fold(strings.trim_space(line[:colon]), name) {
			value = strings.trim_space(line[colon + 1:])
			ok = true
		}
	}
	return
}
