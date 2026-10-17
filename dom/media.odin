package dom

import "core:strconv"
import "core:strings"

// @media support. lexbor skips @media blocks completely (even matching ones),
// so we evaluate them ourselves before lexbor sees the CSS: the rules of a
// matching block are "unwrapped" (kept without the @media around them), a
// block that doesn't match is removed.
//
// The queries are evaluated once, for the viewport size at load time.

// What the media queries are evaluated against.
Media_Env :: struct {
	width, height: f32, // viewport in px
}

DEFAULT_MEDIA :: Media_Env{1024, 768}

// Returns the CSS with matching @media blocks unwrapped and the others removed.
// With only_media, everything outside of @media blocks is dropped: for <style>
// elements, whose other rules lexbor has already applied.
apply_media_queries :: proc(css: string, env: Media_Env, only_media := false, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	write_media_unwrapped(&b, css, env, only_media)
	return strings.to_string(b)
}

@(private)
write_media_unwrapped :: proc(b: ^strings.Builder, css: string, env: Media_Env, only_media: bool) {
	i := 0
	plain_start := 0
	depth := 0
	for i < len(css) {
		switch {
		case strings.has_prefix(css[i:], "/*"):
			i = skip_comment(css, i)
			continue
		case css[i] == '"' || css[i] == '\'':
			i = skip_string(css, i)
			continue
		case css[i] == '{':
			depth += 1
		case css[i] == '}':
			depth = max(depth - 1, 0)
		case depth == 0 && has_prefix_fold(css[i:], "@media"):
			// flush the plain CSS before the block
			if !only_media {
				strings.write_string(b, css[plain_start:i])
			}
			open := find_outside(css, i, '{')
			if open < 0 {
				return // broken CSS: drop the rest
			}
			close := matching_brace(css, open)
			query := strings.trim_space(css[i + len("@media"):open])
			if media_query_list_matches(query, env) {
				// nested @media inside are evaluated too; the inner CSS is
				// written completely (it is the content we want)
				write_media_unwrapped(b, css[open + 1:close], env, false)
				strings.write_byte(b, '\n')
			}
			i = close + 1
			plain_start = i
			continue
		}
		i += 1
	}
	if !only_media {
		strings.write_string(b, css[plain_start:])
	}
}

// "screen and (min-width: 640px), print": true if any of the queries matches.
media_query_list_matches :: proc(list: string, env: Media_Env) -> bool {
	lower := strings.to_lower(list, context.temp_allocator)
	if strings.trim_space(lower) == "" {
		return true // "@media {" means all
	}
	for query in split_outside_parens_by(lower, ',') {
		if media_query_matches(strings.trim_space(query), env) {
			return true
		}
	}
	return false
}

// One query: [not|only] [type] [and (feature)]...
media_query_matches :: proc(query: string, env: Media_Env) -> bool {
	q := query
	negate := false
	if strings.has_prefix(q, "not ") {
		negate = true
		q = strings.trim_space(q[4:])
	} else if strings.has_prefix(q, "only ") {
		q = strings.trim_space(q[5:])
	}

	result := true
	for part in split_on_and(q) {
		part := strings.trim_space(part)
		if part == "" {
			continue
		}
		if strings.has_prefix(part, "(") {
			result &&= media_feature_matches(strings.trim_space(part[1:len(part) - 1]), env)
		} else {
			result &&= part == "all" || part == "screen"
		}
	}
	return result != negate
}

// "min-width: 640px", "prefers-color-scheme: dark", "width >= 640px", "color"
@(private)
media_feature_matches :: proc(feature: string, env: Media_Env) -> bool {
	// range syntax of Media Queries 4: "width >= 640px", "width < 1120px"
	for op in ([]string{">=", "<=", ">", "<", "="}) {
		if i := strings.index(feature, op); i >= 0 {
			name := strings.trim_space(feature[:i])
			value, ok := media_length(strings.trim_space(feature[i + len(op):]))
			if !ok {
				return false
			}
			actual: f32
			switch name {
			case "width":
				actual = env.width
			case "height":
				actual = env.height
			case:
				return false
			}
			switch op {
			case ">=": return actual >= value
			case "<=": return actual <= value
			case ">":  return actual > value
			case "<":  return actual < value
			case "=":  return actual == value
			}
		}
	}

	name, value := feature, ""
	if colon := strings.index_byte(feature, ':'); colon >= 0 {
		name = strings.trim_space(feature[:colon])
		value = strings.trim_space(feature[colon + 1:])
	}
	switch name {
	case "min-width", "max-width", "width", "min-height", "max-height", "height":
		length := media_length(value) or_return
		actual := env.height if strings.has_suffix(name, "height") else env.width
		switch {
		case strings.has_prefix(name, "min-"):
			return actual >= length
		case strings.has_prefix(name, "max-"):
			return actual <= length
		}
		return actual == length
	case "orientation":
		landscape := env.width >= env.height
		return value == ("landscape" if landscape else "portrait")
	case "prefers-color-scheme":
		return value == "light" // we only have a light theme
	case "prefers-reduced-motion", "prefers-reduced-transparency", "prefers-contrast":
		return value == "no-preference"
	case "hover", "any-hover":
		return value == "" || value == "hover" // we have a mouse
	case "pointer", "any-pointer":
		return value == "" || value == "fine"
	case "color":
		return true
	}
	return false // unknown features never match
}

// A length in a media query: px, em/rem (16px) or a simple calc() with + and -,
// like Wikipedia's "calc(1120px - 1px)".
@(private)
media_length :: proc(value: string) -> (px: f32, ok: bool) {
	v := strings.trim_space(value)
	if strings.has_prefix(v, "calc(") && strings.has_suffix(v, ")") {
		v = v[len("calc("):len(v) - 1]
		total: f32 = 0
		sign: f32 = 1
		rest := v
		for word in strings.fields_iterator(&rest) {
			switch word {
			case "+":
				sign = 1
			case "-":
				sign = -1
			case:
				total += sign * (media_length(word) or_return)
			}
		}
		return total, true
	}
	number, unit := split_number(v)
	n := strconv.parse_f32(number) or_return
	switch unit {
	case "px", "":
		return n, true
	case "em", "rem":
		return n * ROOT_FONT_SIZE, true
	}
	return 0, false
}

// Splits "screen and (min-width: 1px) and (x)" at "and", not inside parentheses.
@(private)
split_on_and :: proc(query: string) -> []string {
	parts := make([dynamic]string, context.temp_allocator)
	depth := 0
	start := 0
	for i := 0; i < len(query); i += 1 {
		switch query[i] {
		case '(':
			depth += 1
		case ')':
			depth -= 1
		case ' ':
			if depth == 0 && strings.has_prefix(query[i:], " and ") {
				append(&parts, query[start:i])
				start = i + len(" and ")
				i = start - 1
			}
		}
	}
	append(&parts, query[start:])
	return parts[:]
}

@(private)
split_outside_parens_by :: proc(s: string, sep: u8) -> []string {
	parts := make([dynamic]string, context.temp_allocator)
	depth := 0
	start := 0
	for i := 0; i < len(s); i += 1 {
		switch s[i] {
		case '(':
			depth += 1
		case ')':
			depth -= 1
		case sep:
			if depth == 0 {
				append(&parts, s[start:i])
				start = i + 1
			}
		}
	}
	append(&parts, s[start:])
	return parts[:]
}

// --- a tiny CSS scanner: braces, but not inside comments or strings ---

@(private)
skip_comment :: proc(css: string, i: int) -> int {
	end := strings.index(css[i + 2:], "*/")
	return len(css) if end < 0 else i + 2 + end + 2
}

@(private)
skip_string :: proc(css: string, i: int) -> int {
	quote := css[i]
	j := i + 1
	for j < len(css) && css[j] != quote {
		if css[j] == '\\' {
			j += 1 // escaped character
		}
		j += 1
	}
	return min(j + 1, len(css))
}

// Index of the first c at or after i, outside of comments and strings; -1 if none.
@(private)
find_outside :: proc(css: string, i: int, c: u8) -> int {
	j := i
	for j < len(css) {
		switch {
		case strings.has_prefix(css[j:], "/*"):
			j = skip_comment(css, j)
			continue
		case css[j] == '"' || css[j] == '\'':
			j = skip_string(css, j)
			continue
		case css[j] == c:
			return j
		}
		j += 1
	}
	return -1
}

// Index of the } that closes the { at open (or the end of the text).
@(private)
matching_brace :: proc(css: string, open: int) -> int {
	depth := 0
	j := open
	for j < len(css) {
		switch {
		case strings.has_prefix(css[j:], "/*"):
			j = skip_comment(css, j)
			continue
		case css[j] == '"' || css[j] == '\'':
			j = skip_string(css, j)
			continue
		case css[j] == '{':
			depth += 1
		case css[j] == '}':
			depth -= 1
			if depth == 0 {
				return j
			}
		}
		j += 1
	}
	return len(css) - 1
}

@(private)
has_prefix_fold :: proc(s, prefix: string) -> bool {
	return len(s) >= len(prefix) && strings.equal_fold(s[:len(prefix)], prefix)
}
