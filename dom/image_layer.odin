package dom

import "core:strings"

// An image drawn in or over an element's box: background-image, and
// mask-image, the way pages draw most of their icons (an element with a
// background color, often currentColor, that only shows where the mask image,
// an SVG, is opaque). Only the first layer of a list and only url() images;
// gradients count as no image. Not inherited.
Image_Layer :: struct {
	image:     string,    // the url as written in the CSS ("" = none)
	size:      Layer_Size,
	width:     Length,    // with .Explicit; .Auto follows the image's aspect ratio
	height:    Length,
	position:  [2]Length, // x, y of the free space: 0% = left/top, 100% = right/bottom
	no_repeat: [2]bool,   // x, y (repeat is the initial value)
}

Layer_Size :: enum {
	Auto, // the image's natural size
	Contain,
	Cover,
	Explicit,
}

// mask-* and background-* (image, size, position, repeat) and the shorthands
// mask and background; the mask properties also with the -webkit- prefix
// (many pages still need it). The color of background is read in box_style.odin.
@(private)
apply_image_layer_declaration :: proc(style: ^Style, property: string, value: string) {
	name := strings.trim_prefix(property, "-webkit-")
	target := &style.mask
	if strings.has_prefix(name, "background") {
		target = &style.background_image
	}
	part := name[strings.index_byte(name, '-') + 1:] if strings.contains(name, "-") else ""
	layer := first_layer(value)
	words := strings.fields(strings.to_lower(layer, context.temp_allocator), context.temp_allocator)
	switch part {
	case "":
		apply_layer_shorthand(target, layer)
	case "image":
		target.image = layer_image(layer) or_else target.image
	case "size":
		parse_layer_size(target, layer)
	case "position":
		if position, ok := parse_layer_position(words); ok {
			target.position = position
		}
	case "repeat":
		if no_repeat, ok := parse_layer_repeat(words); ok {
			target.no_repeat = no_repeat
		}
	}
}

// mask / background: <image> <position> [/ <size>] <repeat> ... in any
// order; what is not given goes back to its initial value. Other parts (the
// background color, origin, clip, ...) are skipped.
@(private)
apply_layer_shorthand :: proc(target: ^Image_Layer, value: string) {
	result: Image_Layer
	position_words := make([dynamic]string, context.temp_allocator)
	repeat_words := make([dynamic]string, context.temp_allocator)
	after_slash := false
	size_words := make([dynamic]string, context.temp_allocator)
	for word in split_outside_parens(value, context.temp_allocator) {
		lower := strings.to_lower(word, context.temp_allocator)
		switch {
		case strings.has_prefix(lower, "url("), lower == "none", strings.contains(lower, "gradient("):
			result.image = layer_image(word) or_else ""
		case lower == "/":
			after_slash = true
		case strings.has_prefix(lower, "/"):
			after_slash = true
			append(&size_words, lower[1:])
		case after_slash && (is_length_word(lower) || lower == "contain" || lower == "cover" || lower == "auto"):
			append(&size_words, lower)
		case lower == "repeat" || lower == "no-repeat" || lower == "repeat-x" || lower == "repeat-y" || lower == "space" || lower == "round":
			append(&repeat_words, lower)
		case is_position_word(lower):
			after_slash = false
			append(&position_words, lower)
		}
	}
	if position, ok := parse_layer_position(position_words[:]); ok {
		result.position = position
	}
	if no_repeat, ok := parse_layer_repeat(repeat_words[:]); ok {
		result.no_repeat = no_repeat
	}
	if len(size_words) > 0 {
		parse_layer_size(&result, strings.join(size_words[:], " ", context.temp_allocator))
	}
	target^ = result
}

// The url of an image: "" for none (and for gradients, which we don't draw:
// as if there were no image). Fails for anything else.
@(private)
layer_image :: proc(value: string) -> (image: string, ok: bool) {
	lower := strings.to_lower(strings.trim_space(value), context.temp_allocator)
	switch {
	case lower == "none", lower == "initial", lower == "unset":
		return "", true
	case strings.contains(lower, "gradient("):
		return "", true
	}
	return css_url(value)
}

// url(...) -> its address: the quotes removed and backslash escapes resolved
// (data URLs often contain \" inside a quoted string).
css_url :: proc(value: string) -> (url: string, ok: bool) {
	v := strings.trim_space(value)
	if len(v) < 5 || !strings.equal_fold(v[:4], "url(") || v[len(v) - 1] != ')' {
		return "", false
	}
	inner := strings.trim_space(v[4:len(v) - 1])
	if len(inner) >= 2 && (inner[0] == '"' || inner[0] == '\'') && inner[len(inner) - 1] == inner[0] {
		inner = inner[1:len(inner) - 1]
	}
	if strings.index_byte(inner, '\\') < 0 {
		return inner, true
	}
	b := strings.builder_make(0, len(inner), context.temp_allocator)
	for i := 0; i < len(inner); i += 1 {
		if inner[i] == '\\' && i + 1 < len(inner) {
			i += 1
		}
		strings.write_byte(&b, inner[i])
	}
	return strings.to_string(b), true
}

// contain, cover, or one or two lengths (the second auto by default).
@(private)
parse_layer_size :: proc(layer: ^Image_Layer, value: string) {
	words := strings.fields(strings.to_lower(value, context.temp_allocator), context.temp_allocator)
	switch {
	case len(words) == 1 && words[0] == "contain":
		layer.size = .Contain
	case len(words) == 1 && words[0] == "cover":
		layer.size = .Cover
	case len(words) == 1 && (words[0] == "auto" || words[0] == "initial" || words[0] == "unset"):
		layer.size = .Auto
	case len(words) == 1 || len(words) == 2:
		width, ok := parse_length(words[0], true)
		if !ok {
			return // like max(...): we keep the image's own size
		}
		height := AUTO
		if len(words) == 2 {
			h, h_ok := parse_length(words[1], true)
			if !h_ok {
				return
			}
			height = h
		}
		layer.size, layer.width, layer.height = .Explicit, width, height
		if width.unit == .Auto && height.unit == .Auto {
			layer.size = .Auto
		}
	}
}

// One to four position values: keywords, lengths or percentages. A single
// value means the other axis is centered; with three or four, a keyword can
// be followed by its distance from that edge ("right 4px top").
@(private)
parse_layer_position :: proc(words: []string) -> (position: [2]Length, ok: bool) {
	if len(words) == 0 || len(words) > 4 {
		return {}, false
	}
	center := Length{unit = .Percent, value = 50}
	position = {center, center}
	if len(words) >= 3 {
		return edge_offsets(words)
	}
	// "top left": a vertical keyword first swaps the order
	swapped := axis_of(words[0]) == 1 || (len(words) == 2 && axis_of(words[1]) == 0)
	for word, i in words {
		axis := i if !swapped else 1 - i
		if a := axis_of(word); a >= 0 && len(words) == 1 {
			axis = a
		}
		position[axis] = position_keyword(word) or_return
	}
	return position, true
}

// "right 4px top", "left 10% bottom 2em": keywords, each maybe with an offset.
@(private)
edge_offsets :: proc(words: []string) -> (position: [2]Length, ok: bool) {
	center := Length{unit = .Percent, value = 50}
	position = {center, center}
	for i := 0; i < len(words); i += 1 {
		axis := axis_of(words[i])
		edge := position_keyword(words[i]) or_return
		if axis < 0 {
			if words[i] != "center" {
				return {}, false // a length without a keyword
			}
			continue // center: the axis is the one not named otherwise
		}
		if i + 1 < len(words) && is_length_word(words[i + 1]) {
			offset, _ := parse_length(words[i + 1], false)
			i += 1
			if offset.unit == .Calc {
				return {}, false
			}
			if edge.value == 0 {
				edge = offset
			} else {
				// from the right/bottom: 100% - offset
				edge = Length{unit = .Calc}
				edge.calc[.Percent] = 100
				edge.calc[offset.unit] -= offset.value
			}
		}
		position[axis] = edge
	}
	return position, true
}

@(private)
axis_of :: proc(word: string) -> int {
	switch word {
	case "left", "right":
		return 0
	case "top", "bottom":
		return 1
	}
	return -1 // center or a length: in order
}

@(private)
position_keyword :: proc(word: string) -> (Length, bool) {
	switch word {
	case "left", "top":
		return {unit = .Percent, value = 0}, true
	case "center":
		return {unit = .Percent, value = 50}, true
	case "right", "bottom":
		return {unit = .Percent, value = 100}, true
	}
	return parse_length(word, false)
}

@(private)
parse_layer_repeat :: proc(words: []string) -> (no_repeat: [2]bool, ok: bool) {
	switch len(words) {
	case 1:
		switch words[0] {
		case "repeat", "space", "round":
			return {false, false}, true
		case "no-repeat":
			return {true, true}, true
		case "repeat-x":
			return {false, true}, true
		case "repeat-y":
			return {true, false}, true
		}
	case 2:
		for word, i in words {
			switch word {
			case "repeat", "space", "round":
			case "no-repeat":
				no_repeat[i] = true
			case:
				return {}, false
			}
		}
		return no_repeat, true
	}
	return {}, false
}

// The first of a comma separated list of layers (commas inside url() or
// other functions don't count).
@(private)
first_layer :: proc(value: string) -> string {
	depth := 0
	quote: u8 = 0
	for i := 0; i < len(value); i += 1 {
		c := value[i]
		switch {
		case quote != 0:
			if c == '\\' {
				i += 1 // the escaped character
			} else if c == quote {
				quote = 0
			}
		case c == '"' || c == '\'':
			quote = c
		case c == '(':
			depth += 1
		case c == ')':
			depth -= 1
		case c == ',' && depth == 0:
			return strings.trim_space(value[:i])
		}
	}
	return strings.trim_space(value)
}

@(private)
is_position_word :: proc(word: string) -> bool {
	switch word {
	case "left", "right", "top", "bottom", "center":
		return true
	}
	return is_length_word(word)
}

@(private)
is_length_word :: proc(word: string) -> bool {
	_, ok := parse_length(word, false)
	return ok
}
