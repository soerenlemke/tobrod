package dom

import "core:strconv"
import "core:strings"

// Parsers for CSS values as lexbor serializes them: lowercase, normalized
// separators, but relative units are kept (we resolve them against the parent).

ROOT_FONT_SIZE :: f32(16) // "medium", also the base for rem

// Resolves a font-size value. parent is the parent's computed size in px.
parse_font_size :: proc(value: string, parent: f32) -> (px: f32, ok: bool) {
	switch value {
	case "xx-small":
		return ROOT_FONT_SIZE * 3 / 5, true
	case "x-small":
		return ROOT_FONT_SIZE * 3 / 4, true
	case "small":
		return ROOT_FONT_SIZE * 8 / 9, true
	case "medium":
		return ROOT_FONT_SIZE, true
	case "large":
		return ROOT_FONT_SIZE * 6 / 5, true
	case "x-large":
		return ROOT_FONT_SIZE * 3 / 2, true
	case "xx-large":
		return ROOT_FONT_SIZE * 2, true
	case "xxx-large":
		return ROOT_FONT_SIZE * 3, true
	case "smaller":
		return parent / 1.2, true
	case "larger":
		return parent * 1.2, true
	}

	number, unit := split_number(value)
	n := strconv.parse_f32(number) or_return
	switch unit {
	case "px", "":
		// a bare number is only valid for 0
		if unit == "" && n != 0 {
			return 0, false
		}
		return n, true
	case "em":
		return n * parent, true
	case "rem":
		return n * ROOT_FONT_SIZE, true
	case "%":
		return n / 100 * parent, true
	case "pt":
		return n * 4 / 3, true
	}
	return 0, false
}

// Resolves a font-weight value to a number between 1 and 1000.
// bolder/lighter use the simplified table from the CSS fonts spec.
parse_font_weight :: proc(value: string, parent: int) -> (weight: int, ok: bool) {
	switch value {
	case "normal":
		return 400, true
	case "bold":
		return 700, true
	case "bolder":
		if parent < 350 do return 400, true
		if parent < 550 do return 700, true
		return 900, true
	case "lighter":
		if parent < 550 do return 100, true
		if parent < 750 do return 400, true
		return 700, true
	}
	n := strconv.parse_int(value) or_return
	if n < 1 || n > 1000 {
		return 0, false
	}
	return n, true
}

// Supports named colors (a common subset), #rgb, #rgba, #rrggbb, #rrggbbaa,
// rgb()/rgba() and transparent. currentcolor is the inherited color.
// hsl() and the other color functions are not supported yet.
parse_color :: proc(value: string, current: Color) -> (color: Color, ok: bool) {
	if value == "currentcolor" {
		return current, true
	}
	if strings.has_prefix(value, "#") {
		return parse_hex_color(value[1:])
	}
	if strings.has_prefix(value, "rgb(") || strings.has_prefix(value, "rgba(") {
		return parse_rgb_function(value)
	}
	return named_color(value)
}

@(private)
parse_hex_color :: proc(hex: string) -> (color: Color, ok: bool) {
	digits: [8]u8
	for i in 0 ..< len(hex) {
		if i >= len(digits) do return {}, false
		digits[i] = hex_digit(hex[i]) or_return
	}
	switch len(hex) {
	case 3, 4: // short form: every digit is doubled, #f00 = #ff0000
		alpha := u8(255)
		if len(hex) == 4 do alpha = digits[3] * 17
		return {digits[0] * 17, digits[1] * 17, digits[2] * 17, alpha}, true
	case 6, 8:
		alpha := u8(255)
		if len(hex) == 8 do alpha = digits[6] * 16 + digits[7]
		return {digits[0] * 16 + digits[1], digits[2] * 16 + digits[3], digits[4] * 16 + digits[5], alpha}, true
	}
	return {}, false
}

@(private)
hex_digit :: proc(c: u8) -> (value: u8, ok: bool) {
	switch c {
	case '0' ..= '9':
		return c - '0', true
	case 'a' ..= 'f':
		return c - 'a' + 10, true
	case 'A' ..= 'F':
		return c - 'A' + 10, true
	}
	return 0, false
}

// rgb(255, 0, 0), rgba(255, 0, 0, 0.5), rgb(255 0 0 / 50%), channels also as %
@(private)
parse_rgb_function :: proc(value: string) -> (color: Color, ok: bool) {
	open := strings.index_byte(value, '(')
	close := strings.last_index_byte(value, ')')
	if open < 0 || close < open {
		return {}, false
	}
	args := value[open + 1:close]

	parts: [4]string
	count := 0
	rest := args
	for part in strings.split_multi_iterate(&rest, {",", "/", " "}) {
		if len(part) == 0 do continue
		if count >= len(parts) do return {}, false
		parts[count] = part
		count += 1
	}
	if count != 3 && count != 4 {
		return {}, false
	}

	for i in 0 ..< 3 {
		color[i] = parse_channel(parts[i], 255) or_return
	}
	color[3] = 255
	if count == 4 {
		color[3] = parse_channel(parts[3], 1) or_return
	}
	return color, true
}

// A channel is either a number up to max or a percentage; result is 0..255.
@(private)
parse_channel :: proc(s: string, max: f32) -> (channel: u8, ok: bool) {
	number, unit := split_number(s)
	n := strconv.parse_f32(number) or_return
	switch unit {
	case "%":
		n = n / 100
	case "":
		n = n / max
	case:
		return 0, false
	}
	return u8(clamp(n, 0, 1) * 255 + 0.5), true
}

// Splits "1.5em" into ("1.5", "em").
@(private)
split_number :: proc(value: string) -> (number, unit: string) {
	i := 0
	for i < len(value) {
		c := value[i]
		if (c >= '0' && c <= '9') || c == '.' || c == '-' || c == '+' {
			i += 1
		} else {
			break
		}
	}
	return value[:i], value[i:]
}

@(private)
named_color :: proc(name: string) -> (color: Color, ok: bool) {
	switch name {
	case "transparent": return {0, 0, 0, 0}, true
	case "black":       return {0, 0, 0, 255}, true
	case "silver":      return {192, 192, 192, 255}, true
	case "gray", "grey": return {128, 128, 128, 255}, true
	case "white":       return {255, 255, 255, 255}, true
	case "maroon":      return {128, 0, 0, 255}, true
	case "red":         return {255, 0, 0, 255}, true
	case "purple":      return {128, 0, 128, 255}, true
	case "fuchsia", "magenta": return {255, 0, 255, 255}, true
	case "green":       return {0, 128, 0, 255}, true
	case "lime":        return {0, 255, 0, 255}, true
	case "olive":       return {128, 128, 0, 255}, true
	case "yellow":      return {255, 255, 0, 255}, true
	case "navy":        return {0, 0, 128, 255}, true
	case "blue":        return {0, 0, 255, 255}, true
	case "teal":        return {0, 128, 128, 255}, true
	case "aqua", "cyan": return {0, 255, 255, 255}, true
	case "orange":      return {255, 165, 0, 255}, true
	case "darkgray", "darkgrey": return {169, 169, 169, 255}, true
	case "lightgray", "lightgrey": return {211, 211, 211, 255}, true
	}
	return {}, false
}
