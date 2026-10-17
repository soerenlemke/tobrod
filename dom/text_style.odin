package dom

import "core:strings"

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
