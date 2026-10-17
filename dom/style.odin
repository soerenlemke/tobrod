package dom

import "core:strings"

// Computed style of an element. Only what we use so far.
Style :: struct {
	display: Display,
}

Display :: enum {
	Inline, // default for unknown elements, like in CSS
	Block,
	List_Item,
	None,
}

// Default style of an element before any author CSS, like the built-in
// "user agent stylesheet" of a real browser. Simplified from the HTML spec.
default_style :: proc(tag: string, has_hidden_attribute: bool) -> Style {
	if has_hidden_attribute {
		return {display = .None}
	}
	switch tag {
	case "head", "script", "style", "template", "title", "meta", "link", "base", "noscript":
		// noscript: we have no JS yet, but real browsers with JS enabled hide it too
		return {display = .None}
	case "li":
		return {display = .List_Item}
	case "html", "body", "address", "article", "aside", "blockquote", "dd", "div", "dl", "dt",
	     "fieldset", "figcaption", "figure", "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6",
	     "header", "hr", "main", "nav", "ol", "p", "pre", "section", "table", "tr", "ul", "details", "summary":
		return {display = .Block}
	}
	return {display = .Inline}
}

// Maps a CSS display value as serialized by lexbor to our enum.
// Layout modes we don't support yet fall back to their outer behavior:
// flex/grid/table act like block, inline-block/inline-flex like inline.
parse_display :: proc(value: string) -> (display: Display, ok: bool) {
	// newer CSS allows two keywords ("block flow"), the first one is the outer display
	outer := strings.trim_space(value)
	if i := strings.index_byte(outer, ' '); i >= 0 {
		outer = outer[:i]
	}
	switch outer {
	case "none":
		return .None, true
	case "list-item":
		return .List_Item, true
	case "block", "flex", "grid", "table", "flow-root", "table-row", "table-row-group",
	     "table-header-group", "table-footer-group", "table-caption":
		return .Block, true
	case "inline", "inline-block", "inline-flex", "inline-grid", "inline-table", "table-cell", "contents":
		return .Inline, true
	}
	return .Inline, false
}
