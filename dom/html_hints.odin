package dom

import "core:strconv"
import "core:strings"

// What an element's HTML (not its CSS) says about its look:
// - presentational attributes like <td bgcolor> or <table cellpadding>, which
//   browsers turn into CSS ("presentational hints" in the HTML spec). They
//   come before the author's CSS, so any CSS rule wins over them.
// - <details>: closed, only its <summary> is shown.
@(private)
apply_html_hints :: proc(node: ^Node, style: ^Style, parent: Style) {
	if hidden_by_details(node) {
		style.display = .None
		return
	}
	if node.tag == "summary" && node.parent != nil && node.parent.tag == "details" {
		_, open := attribute(node.parent, "open")
		style.list_style = .Disclosure_Open if open else .Disclosure_Closed
		style.list_inside = true
	}

	for attr in node.attributes {
		if !html_hint_supported(node.tag, attr.name) {
			continue
		}
		value := strings.trim_space(attr.value)
		switch attr.name {
		case "bgcolor":
			style.background = parse_legacy_color(value) or_else style.background
		case "text", "color":
			style.color = parse_legacy_color(value) or_else style.color
		case "size":
			style.font_size = font_size_of_size_attribute(value) or_else style.font_size
		case "align":
			apply_align(node, style, strings.to_lower(value, context.temp_allocator))
		case "valign":
			switch strings.to_lower(value, context.temp_allocator) {
			case "top", "baseline":
				style.vertical_align = .Top
			case "middle", "center":
				style.vertical_align = .Middle
			case "bottom":
				style.vertical_align = .Bottom
			}
		case "width":
			style.width = parse_dimension(value) or_else style.width
		case "height":
			if length, ok := parse_dimension(value); ok && length.unit == .Px {
				style.height = length // percentages of heights count as auto anyway
			}
		case "cellspacing":
			if n, ok := strconv.parse_f32(value); ok && n >= 0 {
				style.border_spacing = n
			}
		case "nowrap":
			style.white_space = .Nowrap
		case "border":
			// <table border> without a number means 1
			n := strconv.parse_f32(value) or_else 1
			for edge in Edge {
				style.border[edge] = {px(max(n, 0)), .Solid, TABLE_BORDER_COLOR}
			}
		}
	}

	// cellpadding and border of the table also apply to its cells
	if node.tag == "td" || node.tag == "th" {
		table := node.parent
		for table != nil && table.tag != "table" {
			table = table.parent
		}
		if table == nil {
			return
		}
		if value, ok := attribute(table, "cellpadding"); ok {
			if n, ok := strconv.parse_f32(strings.trim_space(value)); ok && n >= 0 {
				style.padding = edges(px(n), px(n), px(n), px(n))
			}
		}
		if value, ok := attribute(table, "border"); ok {
			if n := strconv.parse_f32(strings.trim_space(value)) or_else 1; n > 0 {
				for edge in Edge {
					style.border[edge] = {px(1), .Solid, TABLE_BORDER_COLOR}
				}
			}
		}
	}
}

// The attributes apply_html_hints reads (on which elements); the report
// (element_report.odin) counts the others.
html_hint_supported :: proc(tag, name: string) -> bool {
	switch name {
	case "bgcolor":
		switch tag {
		case "body", "table", "thead", "tbody", "tfoot", "tr", "td", "th":
			return true
		}
	case "text":
		return tag == "body"
	case "color", "size":
		return tag == "font"
	case "align":
		switch tag {
		case "table", "img", "td", "th", "tr", "thead", "tbody", "tfoot", "div", "p", "caption",
		     "h1", "h2", "h3", "h4", "h5", "h6":
			return true
		}
	case "valign":
		switch tag {
		case "td", "th", "tr", "thead", "tbody", "tfoot":
			return true
		}
	case "width":
		switch tag {
		case "table", "td", "th", "hr":
			return true
		}
	case "height":
		switch tag {
		case "table", "tr", "td", "th":
			return true
		}
	case "cellpadding", "cellspacing", "border":
		return tag == "table"
	case "nowrap":
		return tag == "td" || tag == "th"
	}
	return false
}

// Browsers draw <table border> as a grey 3D frame (outset); we draw it solid.
@(private)
TABLE_BORDER_COLOR :: Color{128, 128, 128, 255}

// A closed <details> shows only its first <summary>. Text directly inside it
// is hidden by the layout with the same check (text nodes have no style).
hidden_by_details :: proc(node: ^Node) -> bool {
	details := node.parent
	if details == nil || details.tag != "details" {
		return false
	}
	if _, open := attribute(details, "open"); open {
		return false
	}
	if node.kind != .Element || node.tag != "summary" {
		return true
	}
	// only the first summary counts
	for child in details.children {
		if child.kind == .Element && child.tag == "summary" {
			return child != node
		}
	}
	return false
}

// align: text alignment of the content, or for tables and images their place.
@(private)
apply_align :: proc(node: ^Node, style: ^Style, value: string) {
	switch node.tag {
	case "table":
		switch value {
		case "center":
			style.margin[.Left], style.margin[.Right] = AUTO, AUTO
		case "left":
			style.float = .Left
		case "right":
			style.float = .Right
		}
	case "img":
		switch value {
		case "left":
			style.float = .Left
		case "right":
			style.float = .Right
		}
	case:
		switch value {
		case "left", "justify":
			style.text_align = .Left
		case "center", "middle":
			style.text_align = .Legacy_Center
		case "right":
			style.text_align = .Right
		}
	}
}

// A width or height attribute: "100" (px) or "50%".
@(private)
parse_dimension :: proc(value: string) -> (length: Length, ok: bool) {
	if strings.has_suffix(value, "%") {
		n := strconv.parse_f32(value[:len(value) - 1]) or_return
		return {unit = .Percent, value = n}, n >= 0
	}
	n := strconv.parse_f32(strings.trim_suffix(value, "px")) or_return
	return px(n), n >= 0
}

// Colors in attributes: like CSS, but the # is optional ("ff6600").
@(private)
parse_legacy_color :: proc(value: string) -> (color: Color, ok: bool) {
	value := strings.to_lower(value, context.temp_allocator)
	if color, ok = parse_color(value, {}); ok {
		return
	}
	if len(value) == 3 || len(value) == 6 {
		return parse_color(strings.concatenate({"#", value}, context.temp_allocator), {})
	}
	return {}, false
}

// <font size="1".."7">, also relative: "+1", "-2" (to 3, the normal size).
@(private)
font_size_of_size_attribute :: proc(value: string) -> (size: f32, ok: bool) {
	n := strconv.parse_int(strings.trim_prefix(value, "+")) or_return
	if strings.has_prefix(value, "+") || strings.has_prefix(value, "-") {
		n += 3
	}
	// the sizes browsers use: x-small, small, medium, large, x-large, xx-large, xxx-large
	sizes := [7]f32{10, 13, 16, 18, 24, 32, 48}
	return sizes[clamp(n, 1, 7) - 1], true
}
