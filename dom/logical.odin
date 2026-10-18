package dom

import "core:strings"

// Logical properties (margin-inline-start, padding-block, inline-size, ...)
// name sides by the direction of the text: "inline" along the line, "block"
// across the lines, "start"/"end" where the text begins and ends. We only lay
// out horizontal text from left to right, so they are other names for the
// physical sides: inline-start = left, inline-end = right, block-start = top,
// block-end = bottom.
//
// They are applied after the physical properties, so that a common
// `margin: 0; margin-inline-start: 1em` works. A physical declaration (or
// its shorthand) with a higher specificity wins (loses_to_physical); with
// the same one, the logical one does (we don't know which came later).

LOGICAL_PROPERTIES :: [?]string {
	"margin-block", "margin-inline", "margin-block-start", "margin-block-end", "margin-inline-start", "margin-inline-end",
	"padding-block", "padding-inline", "padding-block-start", "padding-block-end", "padding-inline-start", "padding-inline-end",
	"inset-block", "inset-inline", "inset-block-start", "inset-block-end", "inset-inline-start", "inset-inline-end",
	"border-block", "border-inline", "border-block-start", "border-block-end", "border-inline-start", "border-inline-end",
	"border-block-width", "border-block-style", "border-block-color",
	"border-inline-width", "border-inline-style", "border-inline-color",
	"border-block-start-width", "border-block-start-style", "border-block-start-color",
	"border-block-end-width", "border-block-end-style", "border-block-end-color",
	"border-inline-start-width", "border-inline-start-style", "border-inline-start-color",
	"border-inline-end-width", "border-inline-end-style", "border-inline-end-color",
	"inline-size", "block-size", "min-inline-size", "max-inline-size", "min-block-size", "max-block-size",
	"border-start-start-radius", "border-start-end-radius", "border-end-start-radius", "border-end-end-radius",
}

// How a logical property maps to physical ones.
@(private)
Logical :: struct {
	physical: [2]string, // one, or the two sides of a pair ("" = none)
	split:    bool,      // a pair whose value is "start [end]" (margin-block: 1px 2px)
}

@(private)
logical_mapping :: proc(property: string) -> (m: Logical, ok: bool) {
	switch property {
	case "inline-size":
		return {physical = {0 = "width"}}, true
	case "block-size":
		return {physical = {0 = "height"}}, true
	case "min-inline-size":
		return {physical = {0 = "min-width"}}, true
	case "max-inline-size":
		return {physical = {0 = "max-width"}}, true
	case "min-block-size":
		return {physical = {0 = "min-height"}}, true
	case "max-block-size":
		return {physical = {0 = "max-height"}}, true
	case "border-start-start-radius":
		return {physical = {0 = "border-top-left-radius"}}, true
	case "border-start-end-radius":
		return {physical = {0 = "border-top-right-radius"}}, true
	case "border-end-start-radius":
		return {physical = {0 = "border-bottom-left-radius"}}, true
	case "border-end-end-radius":
		return {physical = {0 = "border-bottom-right-radius"}}, true
	case "inset-block":
		return {physical = {"top", "bottom"}, split = true}, true
	case "inset-inline":
		return {physical = {"left", "right"}, split = true}, true
	case "inset-block-start":
		return {physical = {0 = "top"}}, true
	case "inset-block-end":
		return {physical = {0 = "bottom"}}, true
	case "inset-inline-start":
		return {physical = {0 = "left"}}, true
	case "inset-inline-end":
		return {physical = {0 = "right"}}, true
	case "border-block", "border-inline":
		// "1px solid red" for both sides, not split
		side := "top" if property == "border-block" else "left"
		other := "bottom" if property == "border-block" else "right"
		return {physical = {strings.concatenate({"border-", side}, context.temp_allocator), strings.concatenate({"border-", other}, context.temp_allocator)}}, true
	}
	// margin-*, padding-*, border-*: prefix, axis, then optionally the end
	// (-start, -end) and what of the border (-width, -style, -color)
	for prefix in ([]string{"margin", "padding", "border"}) {
		if !strings.has_prefix(property, prefix) {
			continue
		}
		rest := property[len(prefix):] // "-block-start-width"
		start, end: string
		switch {
		case strings.has_prefix(rest, "-block"):
			start, end, rest = "top", "bottom", rest[len("-block"):]
		case strings.has_prefix(rest, "-inline"):
			start, end, rest = "left", "right", rest[len("-inline"):]
		case:
			return {}, false
		}
		switch {
		case strings.has_prefix(rest, "-start"):
			return {physical = {0 = physical_name(prefix, start, rest[len("-start"):])}}, true
		case strings.has_prefix(rest, "-end"):
			return {physical = {0 = physical_name(prefix, end, rest[len("-end"):])}}, true
		case:
			// margin-block, border-inline-width: both sides, "start [end]"
			return {physical = {physical_name(prefix, start, rest), physical_name(prefix, end, rest)}, split = true}, true
		}
	}
	return {}, false
}

// "border" + "top" + "-width" -> "border-top-width"
@(private)
physical_name :: proc(prefix, side, suffix: string) -> string {
	return strings.concatenate({prefix, "-", side, suffix}, context.temp_allocator)
}

// Applies a logical declaration as the physical one(s).
@(private)
apply_logical :: proc(style: ^Style, property, value: string, parent: Style) {
	m, ok := logical_mapping(property)
	if !ok {
		return
	}
	if m.physical[1] == "" {
		apply_declaration(style, m.physical[0], value, parent)
		return
	}
	start_value, end_value := value, value
	if m.split {
		parts := split_outside_parens(value, context.temp_allocator)
		switch len(parts) {
		case 1:
		case 2:
			start_value, end_value = parts[0], parts[1]
		case:
			return // invalid
		}
	}
	apply_declaration(style, m.physical[0], start_value, parent)
	apply_declaration(style, m.physical[1], end_value, parent)
}

// Whether a physical property this logical one sets (or a shorthand of it)
// was declared with a higher specificity: then that one wins.
@(private)
loses_to_physical :: proc(d: ^Declared, property: string) -> bool {
	own := declared_spec(d, property) or_return
	m := logical_mapping(property) or_return
	for physical in m.physical {
		if physical == "" {
			continue
		}
		if spec, ok := declared_spec(d, physical); ok && spec > own {
			return true
		}
		for shorthand in shorthands_of(physical) {
			if shorthand == "" {
				break
			}
			if spec, ok := declared_spec(d, shorthand); ok && spec > own {
				return true
			}
		}
	}
	return false
}
