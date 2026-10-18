package dom

import "core:strings"

// Which font to draw text in. We have two families, Inter (sans-serif) and
// JetBrains Mono (monospace), each regular and bold, and Inter in italic.
// CSS names any font; font-family is a list of wishes, and we take the
// first one we can say something about. Both are inherited.

Font_Family :: enum {
	Sans, // also for serif: we have no serif font
	Mono,
}

// Browsers draw monospace text smaller by default (13px instead of 16px).
MONO_SCALE :: f32(13) / 16

// font-family: "Segoe UI", Consolas, monospace. Names of fonts we don't
// know (web fonts, fonts of other systems) are skipped, like a browser
// skips fonts that aren't installed.
@(private)
parse_font_family :: proc(value: string) -> (family: Font_Family, ok: bool) {
	rest := value
	for name in strings.split_iterator(&rest, ",") {
		name := strings.trim(strings.trim_space(name), "\"'")
		name = strings.to_lower(name, context.temp_allocator)
		if is_mono_font(name) {
			return .Mono, true
		}
		switch name {
		case "serif", "sans-serif", "system-ui", "ui-sans-serif", "ui-serif", "ui-rounded",
		     "cursive", "fantasy", "math", "-apple-system", "blinkmacsystemfont":
			return .Sans, true
		}
	}
	return .Sans, false
}

@(private)
is_mono_font :: proc(name: string) -> bool {
	switch name {
	case "monospace", "ui-monospace", "menlo", "monaco", "consolas", "sfmono-regular":
		return true
	}
	// Courier New, Liberation Mono, Fira Code, Source Code Pro, Lucida Console, ...
	return strings.contains(name, "mono") || strings.contains(name, "courier") ||
		strings.contains(name, "code") || strings.contains(name, "console")
}

// font-style: italic and oblique look the same for us.
@(private)
parse_font_style :: proc(value: string) -> (italic: bool, ok: bool) {
	switch {
	case value == "normal":
		return false, true
	case value == "italic" || strings.has_prefix(value, "oblique"):
		return true, true
	}
	return false, false
}

// The font shorthand: [style] [variant] [weight] size[/line-height] family,
// like "italic bold 14px/1.5 Georgia, serif". Everything it doesn't name
// goes back to its initial value. System fonts (font: menu) are ignored.
@(private)
apply_font_shorthand :: proc(style: ^Style, value: string, parent: Style) {
	parts := split_outside_parens(value, context.temp_allocator)
	italic := false
	weight := ROOT_STYLE.font_weight
	for part, i in parts {
		size_part := part
		line_height := ""
		if slash := strings.index_byte(part, '/'); slash >= 0 {
			size_part, line_height = part[:slash], part[slash + 1:]
		}
		if size, ok := parse_font_size(size_part, parent.font_size); ok {
			// the size: everything after it is the family
			family, _ := parse_font_family(strings.join(parts[i + 1:], " ", context.temp_allocator))
			style.font_size = size
			style.font_weight = weight
			style.font_italic = italic
			style.font_family = family
			style.line_height = {} // normal
			if line_height != "" {
				style.line_height = parse_line_height(line_height, size) or_else {}
			}
			return
		}
		switch {
		case part == "normal" || part == "small-caps":
		case part == "italic" || part == "oblique":
			italic = true
		case:
			w, ok := parse_font_weight(part, parent.font_weight)
			if !ok {
				return // not a font shorthand we understand: ignore it
			}
			weight = w
		}
	}
}
