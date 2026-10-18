package dom

import "core:strings"

// Borders. Like margins, lexbor gives us the shorthands unexpanded:
// "border: 1px solid red" with the three parts in any order, so we
// recognize each word by what it is (a style keyword, a width or a color).

Border :: struct {
	width: Length,
	style: Border_Style,
	color: Maybe(Color), // nil = currentcolor, the element's text color
}

Borders :: [Edge]Border

// Every visible style is drawn as a solid line for now.
Border_Style :: enum {
	None,
	Solid,
}

// CSS initial values: medium width, no style (so not visible), currentcolor
INITIAL_BORDER :: Border{width = {unit = .Px, value = 3}}
INITIAL_BORDERS :: Borders {
	.Top    = INITIAL_BORDER,
	.Right  = INITIAL_BORDER,
	.Bottom = INITIAL_BORDER,
	.Left   = INITIAL_BORDER,
}

apply_border_declaration :: proc(style: ^Style, property, value: string) {
	switch property {
	case "border":
		if border, ok := parse_border(value, style.color); ok {
			style.border = {.Top = border, .Right = border, .Bottom = border, .Left = border}
		}
	case "border-top", "border-right", "border-bottom", "border-left":
		if border, ok := parse_border(value, style.color); ok {
			style.border[edge_of(property)] = border
		}
	case "border-width", "border-style", "border-color":
		// 1 to 4 values, same rules as margin
		parts, ok := expand_four(value)
		if !ok {
			return
		}
		for edge in Edge {
			apply_border_part(&style.border[edge], property[len("border-"):], parts[edge], style.color) or_break
		}
	case:
		// border-top-width, border-left-color, ...
		rest := property[len("border-"):]
		dash := strings.index_byte(rest, '-')
		if dash < 0 {
			return
		}
		edge := edge_of(strings.concatenate({"-", rest[:dash]}, context.temp_allocator))
		apply_border_part(&style.border[edge], rest[dash + 1:], value, style.color)
	}
}

// part is "width", "style" or "color"
@(private)
apply_border_part :: proc(border: ^Border, part, value: string, current: Color) -> (ok: bool) {
	switch part {
	case "width":
		border.width = parse_border_width(value) or_return
	case "style":
		border.style = parse_border_style(value) or_return
	case "color":
		if value == "currentcolor" {
			border.color = nil
		} else {
			border.color = parse_color(value, current) or_return
		}
	case:
		return false
	}
	return true
}

// "1px solid red", "solid", "thick dashed #333", ... Parts that are missing
// get their initial value, like the shorthand demands.
parse_border :: proc(value: string, current: Color) -> (border: Border, ok: bool) {
	border = INITIAL_BORDER
	words := split_outside_parens(value, context.temp_allocator)
	if len(words) == 0 || len(words) > 3 {
		return {}, false
	}
	for word in words {
		if s, is_style := parse_border_style(word); is_style {
			border.style = s
		} else if w, is_width := parse_border_width(word); is_width {
			border.width = w
		} else if word == "currentcolor" {
			border.color = nil
		} else if c, is_color := parse_color(word, current); is_color {
			border.color = c
		} else {
			return {}, false
		}
	}
	return border, true
}

parse_border_width :: proc(value: string) -> (width: Length, ok: bool) {
	switch value {
	case "thin":
		return px(1), true
	case "medium":
		return px(3), true
	case "thick":
		return px(5), true
	}
	width = parse_length(value, false) or_return
	// percentages are not allowed for border widths
	return width, !has_percent(width) && width.value >= 0
}

parse_border_style :: proc(value: string) -> (style: Border_Style, ok: bool) {
	switch value {
	case "none", "hidden":
		return .None, true
	case "solid", "dashed", "dotted", "double", "groove", "ridge", "inset", "outset":
		return .Solid, true
	}
	return .None, false
}

// The 1-4 value rule of margin, padding, border-width, ... on plain words.
@(private)
expand_four :: proc(value: string) -> (parts: [Edge]string, ok: bool) {
	words := split_outside_parens(value, context.temp_allocator)
	switch len(words) {
	case 1:
		return {.Top = words[0], .Right = words[0], .Bottom = words[0], .Left = words[0]}, true
	case 2:
		return {.Top = words[0], .Right = words[1], .Bottom = words[0], .Left = words[1]}, true
	case 3:
		return {.Top = words[0], .Right = words[1], .Bottom = words[2], .Left = words[1]}, true
	case 4:
		return {.Top = words[0], .Right = words[1], .Bottom = words[2], .Left = words[3]}, true
	}
	return {}, false
}

// Splits at spaces, but not inside parentheses: "1px solid rgb(1, 2, 3)"
// gives three parts.
split_outside_parens :: proc(value: string, allocator := context.allocator) -> []string {
	parts := make([dynamic]string, allocator)
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
				append(&parts, part)
			}
			start = i + 1
		}
	}
	return parts[:]
}

// Width in px as drawn: no style means no border at all.
border_width_px :: proc(border: Border, font_size: f32, viewport: [2]f32) -> f32 {
	if border.style == .None {
		return 0
	}
	return resolve_length(border.width, font_size, 0, viewport)
}

// The color as drawn: currentcolor is the element's text color.
border_color :: proc(border: Border, text_color: Color) -> Color {
	if c, ok := border.color.?; ok {
		return c
	}
	return text_color
}
