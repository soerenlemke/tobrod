package dom

import "core:strings"

// mask-image with an image: pages draw most of their icons this way, an
// element with a background color (often currentColor) that only shows where
// the mask image (an SVG) is opaque. Only the first layer and only url()
// images; gradients (used for fading edges) are ignored. Not inherited.
Mask :: struct {
	image:     string,    // the url as written in the CSS ("" = none)
	size:      Mask_Size,
	width:     Length,    // with .Explicit; .Auto follows the image's aspect ratio
	height:    Length,
	position:  [2]Length, // x, y of the free space: 0% = left/top, 100% = right/bottom
	no_repeat: [2]bool,   // x, y (repeat is the initial value)
}

Mask_Size :: enum {
	Auto, // the image's natural size
	Contain,
	Cover,
	Explicit,
}

// The mask properties, also with the -webkit- prefix (many pages still need it).
@(private)
apply_mask_declaration :: proc(style: ^Style, property: string, value: string) {
	name := strings.trim_prefix(property, "-webkit-")
	layer := first_layer(value)
	switch name {
	case "mask":
		apply_mask_shorthand(&style.mask, layer)
	case "mask-image":
		style.mask.image = mask_image(layer) or_else style.mask.image
	case "mask-size":
		parse_mask_size(&style.mask, layer)
	case "mask-position":
		if position, ok := parse_mask_position(strings.fields(strings.to_lower(layer, context.temp_allocator), context.temp_allocator)); ok {
			style.mask.position = position
		}
	case "mask-repeat":
		if no_repeat, ok := parse_mask_repeat(strings.fields(strings.to_lower(layer, context.temp_allocator), context.temp_allocator)); ok {
			style.mask.no_repeat = no_repeat
		}
	}
}

// mask: <image> <position> [/ <size>] <repeat> ... in any order; what is not
// given goes back to its initial value.
@(private)
apply_mask_shorthand :: proc(mask: ^Mask, value: string) {
	result: Mask
	position_words := make([dynamic]string, context.temp_allocator)
	repeat_words := make([dynamic]string, context.temp_allocator)
	after_slash := false
	size_words := make([dynamic]string, context.temp_allocator)
	for word in split_outside_parens(value, context.temp_allocator) {
		lower := strings.to_lower(word, context.temp_allocator)
		switch {
		case strings.has_prefix(lower, "url("), lower == "none", strings.contains(lower, "gradient("):
			result.image = mask_image(word) or_else ""
		case lower == "/":
			after_slash = true
		case strings.has_prefix(lower, "/"):
			after_slash = true
			append(&size_words, lower[1:])
		case after_slash && (is_length_word(lower) || lower == "contain" || lower == "cover"):
			append(&size_words, lower)
		case lower == "repeat" || lower == "no-repeat" || lower == "repeat-x" || lower == "repeat-y" || lower == "space" || lower == "round":
			append(&repeat_words, lower)
		case is_position_word(lower):
			after_slash = false
			append(&position_words, lower)
		}
	}
	if position, ok := parse_mask_position(position_words[:]); ok {
		result.position = position
	}
	if no_repeat, ok := parse_mask_repeat(repeat_words[:]); ok {
		result.no_repeat = no_repeat
	}
	if len(size_words) > 0 {
		parse_mask_size(&result, strings.join(size_words[:], " ", context.temp_allocator))
	}
	mask^ = result
}

// The url of a mask image: "" for none (and for gradients, which we don't
// draw: as if there were no mask). Fails for anything else.
@(private)
mask_image :: proc(value: string) -> (image: string, ok: bool) {
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
parse_mask_size :: proc(mask: ^Mask, value: string) {
	words := strings.fields(strings.to_lower(value, context.temp_allocator), context.temp_allocator)
	switch {
	case len(words) == 1 && words[0] == "contain":
		mask.size = .Contain
	case len(words) == 1 && words[0] == "cover":
		mask.size = .Cover
	case len(words) == 1 && (words[0] == "auto" || words[0] == "initial" || words[0] == "unset"):
		mask.size = .Auto
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
		mask.size, mask.width, mask.height = .Explicit, width, height
		if width.unit == .Auto && height.unit == .Auto {
			mask.size = .Auto
		}
	}
}

// One or two position values: keywords, lengths or percentages. A single
// value means the other axis is centered.
@(private)
parse_mask_position :: proc(words: []string) -> (position: [2]Length, ok: bool) {
	if len(words) == 0 || len(words) > 2 {
		return {}, false
	}
	center := Length{unit = .Percent, value = 50}
	position = {center, center}
	axis_of :: proc(word: string) -> int {
		switch word {
		case "left", "right":
			return 0
		case "top", "bottom":
			return 1
		}
		return -1 // center or a length: in order
	}
	keyword :: proc(word: string) -> (Length, bool) {
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
	// "top left": a vertical keyword first swaps the order
	swapped := axis_of(words[0]) == 1 || (len(words) == 2 && axis_of(words[1]) == 0)
	for word, i in words {
		axis := i if !swapped else 1 - i
		if a := axis_of(word); a >= 0 && len(words) == 1 {
			axis = a
		}
		position[axis] = keyword(word) or_return
	}
	return position, true
}

@(private)
parse_mask_repeat :: proc(words: []string) -> (no_repeat: [2]bool, ok: bool) {
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
