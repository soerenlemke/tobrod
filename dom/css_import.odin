package dom

import "core:strings"

// @import: a stylesheet can pull in other stylesheets at its very start
// (only @charset and @layer statements may come before):
//
//   @import url("basic.css");
//   @import "print.css" print;
//   @import url(wide.css) screen and (min-width: 800px);
//
// The imported rules come before the rules of the importing stylesheet in the
// cascade. The href is relative to the importing stylesheet, not the page.
// layer(...) and supports(...) are ignored (the rules count as unlayered).

@(private)
Css_Import :: struct {
	href:  string,
	media: string, // "" = all
}

// Max depth of stylesheets that import stylesheets, against cycles.
@(private)
MAX_IMPORT_DEPTH :: 5

// Splits the @import rules off the start of a stylesheet. The strings point
// into css; rest is the stylesheet without them.
@(private)
split_imports :: proc(css: string, allocator := context.temp_allocator) -> (imports: [dynamic]Css_Import, rest: string) {
	imports = make([dynamic]Css_Import, allocator)
	i := 0
	for {
		// whitespace and comments
		for i < len(css) {
			if strings.has_prefix(css[i:], "/*") {
				i = skip_comment(css, i)
			} else if strings.is_space(rune(css[i])) {
				i += 1
			} else {
				break
			}
		}
		at := css[i:]
		switch {
		case has_prefix_fold(at, "@charset"), has_prefix_fold(at, "@layer"):
			// statements that may come first; "@layer x { ... }" is a block
			// and ends the imports
			end := find_outside(css, i, ';')
			brace := find_outside(css, i, '{')
			if end < 0 || (brace >= 0 && brace < end) {
				return imports, css[i:]
			}
			i = end + 1
		case has_prefix_fold(at, "@import"):
			end := find_outside(css, i, ';')
			if end < 0 {
				end = len(css)
			}
			if imp, ok := parse_import(css[i + len("@import"):end]); ok {
				append(&imports, imp)
			}
			i = min(end + 1, len(css))
		case:
			return imports, css[i:]
		}
	}
}

// The part after "@import": url(...) or a string, then the media list.
@(private)
parse_import :: proc(prelude: string) -> (imp: Css_Import, ok: bool) {
	p := strings.trim_space(prelude)
	rest: string
	switch {
	case has_prefix_fold(p, "url("):
		close := strings.index_byte(p, ')')
		if close < 0 {
			return
		}
		imp.href = strings.trim(strings.trim_space(p[len("url("):close]), "\"'")
		rest = p[close + 1:]
	case len(p) > 0 && (p[0] == '"' || p[0] == '\''):
		end := skip_string(p, 0)
		imp.href = p[1:max(end - 1, 1)]
		rest = p[end:]
	case:
		return
	}

	// what is left: [layer | layer(...)] [supports(...)] [media list]
	rest = strings.trim_space(rest)
	for {
		if has_prefix_fold(rest, "layer(") || has_prefix_fold(rest, "supports(") {
			close := strings.index_byte(rest, ')')
			rest = strings.trim_space(rest[close + 1:]) if close >= 0 else ""
		} else if has_prefix_fold(rest, "layer") && (len(rest) == 5 || rest[5] == ' ') {
			rest = strings.trim_space(rest[5:])
		} else {
			break
		}
	}
	imp.media = rest
	return imp, imp.href != ""
}
