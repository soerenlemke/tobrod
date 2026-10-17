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
}

Length_Unit :: enum {
	Px,
	Em,
	Percent,
	Auto,
}

AUTO :: Length{unit = .Auto}

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
	return {.Px, v}
}

em :: proc(v: f32) -> Length {
	return {.Em, v}
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
		style.margin = edges(em(0.5), AUTO, em(0.5), AUTO)
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
		// the shorthand can contain an image, position, repeat, ...;
		// we only take the color out of it
		if color, ok := background_color_of(value, style.color); ok {
			style.background = color
		}
	}
}

// "1em", "12px", "50%", "auto", "0". allow_auto: auto is only valid for some
// properties (margin, width), not for padding.
parse_length :: proc(value: string, allow_auto: bool) -> (length: Length, ok: bool) {
	if value == "auto" {
		return AUTO, allow_auto
	}
	number, unit := split_number(value)
	n := strconv.parse_f32(number) or_return
	switch unit {
	case "px":
		return px(n), true
	case "":
		// a bare number is only valid for 0
		return px(0), n == 0
	case "em":
		return em(n), true
	case "rem":
		return px(n * ROOT_FONT_SIZE), true
	case "%":
		return {.Percent, n}, true
	case "pt":
		return px(n * 4 / 3), true
	}
	return {}, false
}

// The shorthand rules: 1 value = all sides, 2 = vertical horizontal,
// 3 = top horizontal bottom, 4 = top right bottom left.
parse_edges :: proc(value: string, allow_auto: bool) -> (result: Edges, ok: bool) {
	parts: [4]Length
	count := 0
	rest := value
	for word in strings.fields_iterator(&rest) {
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
// Splits at spaces outside of parentheses, so "rgb(1, 2, 3)" stays one part.
@(private)
background_color_of :: proc(value: string, current: Color) -> (color: Color, ok: bool) {
	depth := 0
	start := 0
	for i := 0; i <= len(value); i += 1 {
		at_end := i == len(value)
		if !at_end {
			switch value[i] {
			case '(':
				depth += 1
			case ')':
				depth -= 1
			}
		}
		if at_end || (value[i] == ' ' && depth == 0) {
			if part := value[start:i]; part != "" {
				if color, ok = parse_color(part, current); ok {
					return
				}
			}
			start = i + 1
		}
	}
	return {}, false
}

@(private)
edge_of :: proc(property: string) -> Edge {
	switch {
	case strings.has_suffix(property, "-top"):
		return .Top
	case strings.has_suffix(property, "-right"):
		return .Right
	case strings.has_suffix(property, "-bottom"):
		return .Bottom
	}
	return .Left
}

// Resolves a length to px. em uses the element's font size, % the width of
// the containing block. auto resolves to 0 here; the layout handles auto margins.
resolve_length :: proc(length: Length, font_size, containing_width: f32) -> f32 {
	switch length.unit {
	case .Px:
		return length.value
	case .Em:
		return length.value * font_size
	case .Percent:
		return length.value / 100 * containing_width
	case .Auto:
		return 0
	}
	return 0
}
