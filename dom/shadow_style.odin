package dom

import "core:strings"

// box-shadow: a list of shadows, the first one on top. Each one is
// "[inset] <x> <y> [<blur> [<spread>]] [<color>]" in any order of the color
// and inset. Pages use outer shadows for cards and popups, and inset ones
// with spread and no blur as borders that don't take up space (GitHub).
// Not inherited.
MAX_SHADOWS :: 4

Shadow :: struct {
	x, y, blur, spread: Length,
	color:              Maybe(Color), // nil = currentcolor
	inset:              bool,
}

Shadows :: struct {
	list:  [MAX_SHADOWS]Shadow,
	count: int,
}

@(private)
parse_box_shadow :: proc(value: string, current: Color) -> (shadows: Shadows, ok: bool) {
	v := strings.trim_space(value)
	if v == "none" || v == "initial" || v == "unset" {
		return {}, true
	}
	for layer in split_layers(v) {
		shadow := parse_shadow(layer, current) or_return
		if shadows.count < MAX_SHADOWS {
			shadows.list[shadows.count] = shadow
			shadows.count += 1
		}
	}
	return shadows, shadows.count > 0
}

@(private)
parse_shadow :: proc(value: string, current: Color) -> (shadow: Shadow, ok: bool) {
	lengths: [4]Length
	count := 0
	for word in split_outside_parens(value, context.temp_allocator) {
		if word == "inset" {
			shadow.inset = true
			continue
		}
		if length, is_length := parse_length(word, false); is_length && !has_percent(length) {
			if count == 4 {
				return {}, false
			}
			lengths[count] = length
			count += 1
			continue
		}
		if word == "currentcolor" {
			shadow.color = nil
			continue
		}
		color := parse_color(word, current) or_return
		shadow.color = color
	}
	if count < 2 {
		return {}, false
	}
	shadow.x, shadow.y, shadow.blur, shadow.spread = lengths[0], lengths[1], lengths[2], lengths[3]
	if shadow.blur.value < 0 {
		return {}, false // a negative blur is invalid
	}
	return shadow, true
}

// A comma separated list, split outside of parentheses (rgb(1, 2, 3)).
@(private)
split_layers :: proc(value: string) -> []string {
	result := make([dynamic]string, context.temp_allocator)
	rest := value
	for len(rest) > 0 {
		layer := first_layer(rest)
		append(&result, layer)
		end := strings.index(rest, layer) + len(layer)
		rest = strings.trim_left(rest[end:], " ,")
	}
	return result[:]
}
