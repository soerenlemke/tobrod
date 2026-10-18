package dom

import "core:strconv"
import "core:strings"

// line-height: the height of the line box of a piece of text. A number is
// inherited as a number (each child multiplies it with its own font size);
// lengths and percentages are turned into px where they are declared and
// inherited as px - like in CSS. normal is 1.25 x the font size, a bit more
// than Inter's own 1.21.

NORMAL_LINE_HEIGHT :: f32(1.25)

Line_Height :: struct {
	unit:  enum {
		Normal, // the zero value: NORMAL_LINE_HEIGHT x the font size
		Factor,
		Px,
	},
	value: f32,
}

// The line height in px for text in this style.
line_height_px :: proc(style: Style) -> f32 {
	switch style.line_height.unit {
	case .Factor:
		return style.line_height.value * style.font_size
	case .Px:
		return style.line_height.value
	case .Normal:
	}
	return NORMAL_LINE_HEIGHT * style.font_size
}

// "normal", "1.5", "24px", "1.5em", "150%"; font_size is the element's own.
@(private)
parse_line_height :: proc(value: string, font_size: f32) -> (Line_Height, bool) {
	if value == "normal" {
		return {}, true
	}
	if n, ok := strconv.parse_f32(value); ok {
		return {.Factor, max(n, 0)}, true
	}
	length, ok := parse_length(value, false)
	if !ok {
		return {}, false
	}
	#partial switch length.unit {
	case .Px:
		return {unit = .Px, value = max(length.value, 0)}, true
	case .Em:
		return {unit = .Px, value = max(length.value * font_size, 0)}, true
	case .Percent:
		return {unit = .Px, value = max(length.value / 100 * font_size, 0)}, true
	}
	return {}, false // vw/vh: not supported here
}

// Text decoration: lines drawn under, over or through the text.
//
// text-decoration is not inherited, but the lines of an element are drawn
// through all text inside it ("propagated"): a span inside an underlined link
// is underlined too, and `text-decoration: none` on the span can't take that
// away. So an element has its own lines (text_decoration_line/-color, from
// the UA stylesheet or CSS) and the lines that apply to its text
// (decoration = its own plus those of its ancestors). The color is that of
// the element that declares the lines; with lines from several elements we
// draw them all in the innermost one's color.

Decoration_Line :: enum {
	Underline,
	Overline,
	Line_Through,
}

Decoration_Lines :: bit_set[Decoration_Line]

Decoration :: struct {
	lines: Decoration_Lines,
	color: Color,
}

// Text properties that are not about the font; called by apply_declaration.
apply_text_declaration :: proc(style: ^Style, property, value: string) {
	switch property {
	case "text-decoration", "-webkit-text-decoration":
		// shorthand: lines, style, color and thickness in any order; what is
		// missing goes back to its initial value
		lines: Decoration_Lines
		color: Maybe(Color)
		for word in split_outside_parens(value, context.temp_allocator) {
			if line, ok := parse_decoration_line(word); ok {
				lines += line
			} else if c, ok := parse_color(word, style.color); ok {
				color = c
			}
			// solid/double/dotted/dashed/wavy and the thickness are drawn as a
			// thin solid line
		}
		style.text_decoration_line = lines
		style.text_decoration_color = color
	case "text-decoration-line", "-webkit-text-decoration-line":
		lines: Decoration_Lines
		rest := value
		for word in strings.fields_iterator(&rest) {
			if line, ok := parse_decoration_line(word); ok {
				lines += line
			}
		}
		style.text_decoration_line = lines
	case "text-decoration-color", "-webkit-text-decoration-color":
		if value == "currentcolor" || value == "initial" {
			style.text_decoration_color = nil
		} else if c, ok := parse_color(value, style.color); ok {
			style.text_decoration_color = c
		}
	}
}

// "underline" -> {.Underline}; "none" and "blink" are no lines.
@(private)
parse_decoration_line :: proc(word: string) -> (Decoration_Lines, bool) {
	switch word {
	case "underline":
		return {.Underline}, true
	case "overline":
		return {.Overline}, true
	case "line-through":
		return {.Line_Through}, true
	case "none", "blink":
		return {}, true
	}
	return {}, false
}

// The lines for the text of an element: those of its ancestors plus its own,
// once its color is known (the end of compute_style).
@(private)
propagate_decoration :: proc(style: ^Style, parent: Style) {
	style.decoration = parent.decoration
	if style.text_decoration_line != {} {
		style.decoration.lines += style.text_decoration_line
		style.decoration.color = style.text_decoration_color.? or_else style.color
	}
}

// white-space: what happens to spaces and line breaks in the text, and
// whether lines wrap.
//
//   value     spaces     line breaks   wrapping
//   normal    collapse   are spaces    yes
//   nowrap    collapse   are spaces    no
//   pre       kept       kept          no
//   pre-wrap  kept       kept          yes   (also break-spaces)
//   pre-line  collapse   kept          yes
White_Space :: enum {
	Normal,
	Nowrap,
	Pre,
	Pre_Wrap,
	Pre_Line,
}

@(private)
parse_white_space :: proc(value: string) -> (White_Space, bool) {
	switch value {
	case "normal", "initial":
		return .Normal, true
	case "nowrap":
		return .Nowrap, true
	case "pre":
		return .Pre, true
	case "pre-wrap", "break-spaces":
		return .Pre_Wrap, true
	case "pre-line":
		return .Pre_Line, true
	}
	return .Normal, false
}

// Whether spaces and line breaks are kept (pre, pre-wrap) or collapsed.
keeps_spaces :: proc(white_space: White_Space) -> bool {
	return white_space == .Pre || white_space == .Pre_Wrap
}

// Whether lines may wrap where they get too long.
wraps :: proc(white_space: White_Space) -> bool {
	return white_space != .Nowrap && white_space != .Pre
}

Text_Transform :: enum {
	None,
	Uppercase,
	Lowercase,
	Capitalize, // the first letter of each word
}
