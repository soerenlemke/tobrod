package dom

import "core:strings"

// The HTML side of the Css_Report: elements and attributes a browser renders
// in its own way that we don't (yet). CSS doesn't show them - a <select> or
// <td bgcolor> looks wrong without any CSS involved.
//
// Only visible elements count (no display: none on them or an ancestor),
// because pages hide a lot of markup (menus, dialogs, templates) that would
// make a gap look more important than it is. <noscript> is the exception:
// it is hidden on purpose, see below.

// Element -> what a browser does that we don't. Some only show the element's
// look from the UA stylesheet (italic, monospace) that we can't draw yet.
ELEMENT_GAPS :: [?][2]string {
	{"input: range", "drawn as a text field"},
	{"input: color", "drawn as a text field"},
	{"input: date", "drawn as a text field"},
	{"input: time", "drawn as a text field"},
	{"progress", "form control, nothing is drawn"},
	{"meter", "form control, nothing is drawn"},
	{"svg", "inline SVG, needs an SVG renderer"},
	{"img: SVG", "<img> with an SVG source, we can't decode it"},
	{"img: WebP", "<img> with a WebP source, we can't decode it"},
	{"math", "MathML"},
	{"canvas", "drawn by JavaScript"},
	{"iframe", "another document, we draw an empty box"},
	{"audio", "media player"},
	{"video", "media player (we show the poster)"},
	{"object", "plugin content"},
	{"embed", "plugin content"},
	{"dialog", "hidden unless open"},
	{"noscript", "we hide it, but have no JavaScript"},
	{"q", "quotation marks"},
	{"ruby", "annotations above the text"},
	{"marquee", "scrolling text"},
	{"custom elements", "<my-element>, usually filled in by JavaScript"},
}

// Presentational attributes (HTML's "presentational hints"): browsers turn
// them into CSS. Counted are those we ignore: not the ones html_hints.odin
// reads, and not width/height of images and the like.
PRESENTATIONAL_ATTRIBUTES :: [?]string {
	"bgcolor", "background", "text", "link", "vlink", "alink", "color", "face", "size",
	"align", "valign", "width", "height", "cellpadding", "cellspacing", "border",
	"nowrap", "hspace", "vspace", "clear", "frame", "rules", "noshade", "type", "start",
}

// Called by copy_children for every element, once its style is known.
@(private)
report_node :: proc(r: ^Css_Report, node: ^Node) {
	// noscript is display: none by our UA stylesheet; it counts if the
	// surrounding page is visible
	if node.tag == "noscript" {
		if node.parent == nil || is_visible(node.parent) {
			report_count(r, &r.elements, "noscript")
		}
		return
	}
	if !is_visible(node) {
		return
	}
	// the parts of an SVG or a formula count as the whole
	for n := node.parent; n != nil; n = n.parent {
		if n.tag == "svg" || n.tag == "math" {
			return
		}
	}
	if key, ok := element_gap(node); ok {
		report_count(r, &r.elements, key)
	}
	for attr in node.attributes {
		if is_presentational(node, attr.name) && !html_hint_supported(node.tag, attr.name) {
			report_count(r, &r.attributes, strings.concatenate({node.tag, "[", attr.name, "]"}, context.temp_allocator))
		}
	}
}

// The reason for a key of Css_Report.elements, for the table of the tool.
element_gap_reason :: proc(key: string) -> string {
	for gap in ELEMENT_GAPS {
		if gap[0] == key {
			return gap[1]
		}
	}
	return ""
}

@(private)
is_visible :: proc(node: ^Node) -> bool {
	for n := node; n != nil && n.kind == .Element; n = n.parent {
		if n.style.display == .None {
			return false
		}
	}
	return true
}

// The key in ELEMENT_GAPS for this element, if it has one.
@(private)
element_gap :: proc(node: ^Node) -> (key: string, ok: bool) {
	switch node.tag {
	case "input":
		// the types we don't draw (yet): as a text field
		type, _ := attribute(node, "type")
		type = strings.to_lower(type, context.temp_allocator)
		switch type {
		case "range", "color", "date", "time":
			return strings.concatenate({"input: ", type}, context.temp_allocator), true
		case "datetime-local", "month", "week":
			return "input: date", true
		}
		return "", false
	case "img":
		src, _ := attribute(node, "src")
		src = strings.to_lower(src, context.temp_allocator)
		if i := strings.index_any(src, "?#"); i >= 0 {
			src = src[:i]
		}
		switch {
		case strings.has_suffix(src, ".svg") || strings.has_prefix(src, "data:image/svg"):
			return "img: SVG", true
		case strings.has_suffix(src, ".webp") || strings.has_prefix(src, "data:image/webp"):
			return "img: WebP", true
		}
		return "", false
	case "dialog":
		// open ones look (roughly) right
		_, open := attribute(node, "open")
		return node.tag, !open
	}
	if strings.contains_rune(node.tag, '-') {
		return "custom elements", true
	}
	for gap in ELEMENT_GAPS {
		if gap[0] == node.tag {
			return node.tag, true
		}
	}
	return "", false
}

@(private)
is_presentational :: proc(node: ^Node, name: string) -> bool {
	switch name {
	case "width", "height":
		// we read the size of replaced elements
		switch node.tag {
		case "img", "video", "iframe", "canvas", "embed", "object", "svg", "source", "input":
			return false
		}
	case "type":
		// only the list numbering style is presentational
		return node.tag == "ol" || node.tag == "ul" || node.tag == "li"
	case "size", "color", "face":
		return node.tag == "font" || node.tag == "hr" || node.tag == "basefont"
	case "border":
		return node.tag == "table" || node.tag == "img"
	case "text", "link", "vlink", "alink":
		return node.tag == "body"
	case "background":
		return node.tag == "body" || node.tag == "table" || node.tag == "td" || node.tag == "th" || node.tag == "tr"
	case "clear":
		return node.tag == "br"
	case "align":
		// <caption align>, <img align>, <td align>, <div align>, ...
		return true
	}
	for a in PRESENTATIONAL_ATTRIBUTES {
		if a == name {
			return true
		}
	}
	return false
}
