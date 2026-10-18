package dom

import "core:strconv"
import "core:strings"

// The CSS box model: margin, padding, width and background of block boxes.
// These properties are not inherited.

// A CSS length. em and % can only be resolved later: em against the element's
// final font size, % against the width of the containing block (in layout).
Length :: struct {
	unit:  Length_Unit,
	value: f32,
	calc:  [Length_Unit]f32, // only for .Calc: the length is the sum of these (calc.odin)
}

Length_Unit :: enum {
	Px,
	Em,
	Percent,
	Vw, // percent of the viewport width
	Vh, // percent of the viewport height
	Auto,
	Calc, // a calc() that mixes units, like calc(100% - 2em)
}

AUTO :: Length{unit = .Auto}

AUTO_EDGES :: Edges{.Top = AUTO, .Right = AUTO, .Bottom = AUTO, .Left = AUTO}

// top, right, bottom, left – the order CSS uses everywhere
Edges :: [Edge]Length

Edge :: enum {
	Top,
	Right,
	Bottom,
	Left,
}

// Edges in CSS order (top, right, bottom, left), like the margin shorthand.
edges :: proc(top, right, bottom, left: Length) -> Edges {
	return {.Top = top, .Right = right, .Bottom = bottom, .Left = left}
}

px :: proc(v: f32) -> Length {
	return {unit = .Px, value = v}
}

em :: proc(v: f32) -> Length {
	return {unit = .Em, value = v}
}

// Default margins and paddings of the user agent stylesheet (HTML spec,
// simplified). Before, these were hardcoded in the layout.
default_box :: proc(tag: string, style: ^Style) {
	switch tag {
	case "body":
		style.margin = edges(px(8), px(8), px(8), px(8))
	case "p", "dl", "pre":
		style.margin = edges(em(1), {}, em(1), {})
	case "ul", "ol":
		style.margin = edges(em(1), {}, em(1), {})
		style.padding[.Left] = px(40) // room for the list markers
	case "blockquote", "figure":
		style.margin = edges(em(1), px(40), em(1), px(40))
	case "dd":
		style.margin[.Left] = px(40)
	case "td", "th":
		style.padding = edges(px(1), px(1), px(1), px(1))
	case "h1":
		style.margin = edges(em(0.67), {}, em(0.67), {})
	case "h2":
		style.margin = edges(em(0.83), {}, em(0.83), {})
	case "h3":
		style.margin = edges(em(1), {}, em(1), {})
	case "h4":
		style.margin = edges(em(1.33), {}, em(1.33), {})
	case "h5":
		style.margin = edges(em(1.67), {}, em(1.67), {})
	case "h6":
		style.margin = edges(em(2.33), {}, em(2.33), {})
	case "hr":
		// a 1px grey line: an empty block with a top and bottom border
		style.margin = edges(em(0.5), AUTO, em(0.5), AUTO)
		for edge in Edge {
			style.border[edge] = {px(1), .Solid, Color{128, 128, 128, 255}}
		}
	}
}

// Box properties from the cascade. lexbor does not expand shorthands, so
// "margin: 0 auto" arrives as "margin" and we split it into the four sides.
apply_box_declaration :: proc(style: ^Style, property, value: string) {
	switch property {
	case "margin":
		if edges, ok := parse_edges(value, true); ok {
			style.margin = edges
		}
	case "padding":
		if edges, ok := parse_edges(value, false); ok {
			style.padding = edges
		}
	case "margin-top", "margin-right", "margin-bottom", "margin-left":
		if length, ok := parse_length(value, true); ok {
			style.margin[edge_of(property)] = length
		}
	case "padding-top", "padding-right", "padding-bottom", "padding-left":
		if length, ok := parse_length(value, false); ok && length.value >= 0 {
			style.padding[edge_of(property)] = length
		}
	case "width":
		if length, ok := parse_length(value, true); ok {
			style.width = length
		}
	case "height":
		if length, ok := parse_length(value, true); ok {
			style.height = length
		}
	case "inset":
		if edges, ok := parse_edges(value, true); ok {
			style.offset = edges
		}
	case "top", "right", "bottom", "left":
		if length, ok := parse_length(value, true); ok {
			style.offset[edge_of(property)] = length
		}
	case "clip":
		if value == "auto" || value == "initial" {
			style.clip = nil
		} else if edges, ok := parse_clip_rect(value); ok {
			style.clip = edges
		}
	case "min-height":
		if value == "auto" {
			style.min_height = {} // like 0 for blocks
		} else if length, ok := parse_length(value, false); ok {
			style.min_height = length
		}
	case "max-height":
		if value == "none" {
			style.max_height = AUTO
		} else if length, ok := parse_length(value, false); ok {
			style.max_height = length
		}
	case "min-width":
		if value == "auto" {
			style.min_width = {} // like 0 outside of flex items
		} else if length, ok := parse_length(value, false); ok {
			style.min_width = length
		}
	case "box-sizing":
		switch value {
		case "border-box":
			style.border_box = true
		case "content-box", "initial":
			style.border_box = false
		}
	case "max-width":
		if value == "none" {
			style.max_width = AUTO
		} else if length, ok := parse_length(value, false); ok {
			style.max_width = length
		}
	case "background-color":
		if color, ok := parse_color(value, style.color); ok {
			style.background = color
		}
	case "background":
		// the shorthand can contain an image, position, repeat, ...; we only
		// take the color out of it. Without one, the color is reset to
		// transparent ("background: none" on a button removes its grey).
		if color, ok := background_color_of(value, style.color); ok {
			style.background = color
		} else if value != "inherit" && value != "unset" && !strings.contains(value, "var(") {
			style.background = {}
		}
	case:
		if strings.has_prefix(property, "border") {
			apply_border_declaration(style, property, value)
		}
	}
}

// "1em", "12px", "50%", "auto", "0". allow_auto: auto is only valid for some
// properties (margin, width), not for padding.
parse_length :: proc(value: string, allow_auto: bool) -> (length: Length, ok: bool) {
	if value == "auto" {
		return AUTO, allow_auto
	}
	if strings.has_prefix(value, "calc(") {
		return parse_calc(value)
	}
	number, unit := split_number(value)
	n := strconv.parse_f32(number) or_return
	if unit == "" {
		// a bare number is only valid for 0
		return px(0), n == 0
	}
	return length_with_unit(n, unit)
}

// A number with a unit, like 2 and "em". rem and pt are converted to px.
@(private)
length_with_unit :: proc(n: f32, unit: string) -> (length: Length, ok: bool) {
	switch unit {
	case "px":
		return px(n), true
	case "em":
		return em(n), true
	case "rem":
		return px(n * ROOT_FONT_SIZE), true
	case "%":
		return {unit = .Percent, value = n}, true
	case "pt":
		return px(n * 4 / 3), true
	case "vw":
		return {unit = .Vw, value = n}, true
	case "vh":
		return {unit = .Vh, value = n}, true
	}
	return {}, false
}

// The shorthand rules: 1 value = all sides, 2 = vertical horizontal,
// 3 = top horizontal bottom, 4 = top right bottom left.
parse_edges :: proc(value: string, allow_auto: bool) -> (result: Edges, ok: bool) {
	parts: [4]Length
	count := 0
	for word in split_outside_parens(value, context.temp_allocator) {
		if count == 4 {
			return {}, false
		}
		parts[count] = parse_length(word, allow_auto) or_return
		count += 1
	}
	switch count {
	case 1:
		return edges(parts[0], parts[0], parts[0], parts[0]), true
	case 2:
		return edges(parts[0], parts[1], parts[0], parts[1]), true
	case 3:
		return edges(parts[0], parts[1], parts[2], parts[1]), true
	case 4:
		return edges(parts[0], parts[1], parts[2], parts[3]), true
	}
	return {}, false
}

// Finds the color in a background shorthand like "#222 url(x.png) no-repeat".
@(private)
background_color_of :: proc(value: string, current: Color) -> (color: Color, ok: bool) {
	for part in split_outside_parens(value, context.temp_allocator) {
		if color, ok = parse_color(part, current); ok {
			return
		}
	}
	return {}, false
}

// rect(top, right, bottom, left), with commas or (old syntax) spaces.
@(private)
parse_clip_rect :: proc(value: string) -> (edges: Edges, ok: bool) {
	if !strings.has_prefix(value, "rect(") || !strings.has_suffix(value, ")") {
		return
	}
	inner, _ := strings.replace_all(value[len("rect("):len(value) - 1], ",", " ", context.temp_allocator)
	return parse_edges(inner, true)
}

@(private)
edge_of :: proc(property: string) -> Edge {
	switch {
	case strings.has_suffix(property, "top"):
		return .Top
	case strings.has_suffix(property, "right"):
		return .Right
	case strings.has_suffix(property, "bottom"):
		return .Bottom
	}
	return .Left
}

// Resolves a length to px. em uses the element's font size, % the width of
// the containing block, vw/vh the size of the viewport (the visible page area).
// auto resolves to 0 here; the layout handles auto margins.
resolve_length :: proc(length: Length, font_size, containing_width: f32, viewport: [2]f32) -> f32 {
	switch length.unit {
	case .Px:
		return length.value
	case .Em:
		return length.value * font_size
	case .Percent:
		return length.value / 100 * containing_width
	case .Vw:
		return length.value / 100 * viewport.x
	case .Vh:
		return length.value / 100 * viewport.y
	case .Auto:
		return 0
	case .Calc:
		sum: f32 = 0
		for value, unit in length.calc {
			if value != 0 {
				sum += resolve_length({unit = unit, value = value}, font_size, containing_width, viewport)
			}
		}
		return sum
	}
	return 0
}
