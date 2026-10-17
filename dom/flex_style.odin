package dom

import "core:strconv"
import "core:strings"

// Flexbox properties (not inherited). The container has direction, wrap,
// justify, align_items and the gaps; the items grow, shrink, basis and
// align_self. The layout is in layout/flex.odin.

Flex :: struct {
	direction:   Flex_Direction,
	wrap:        bool,
	justify:     Justify,
	align_items: Align,
	align_self:  Align_Self,
	row_gap:     Length,
	column_gap:  Length,
	grow:        f32,
	shrink:      f32,    // 1 by default
	basis:       Length, // .Auto by default: use width or the content size
}

Flex_Direction :: enum {
	Row,
	Row_Reverse,
	Column,
	Column_Reverse,
}

Justify :: enum {
	Start,
	End,
	Center,
	Space_Between,
	Space_Around,
	Space_Evenly,
}

Align :: enum {
	Stretch,
	Start,
	End,
	Center,
}

Align_Self :: enum {
	Auto, // use the container's align-items
	Stretch,
	Start,
	End,
	Center,
}

INITIAL_FLEX :: Flex {
	shrink = 1,
	basis  = AUTO,
}

apply_flex_declaration :: proc(style: ^Style, property, value: string) {
	f := &style.flex
	switch property {
	case "flex-direction":
		f.direction = parse_flex_direction(value) or_else f.direction
	case "flex-wrap":
		switch value {
		case "wrap", "wrap-reverse":
			f.wrap = true
		case "nowrap", "initial":
			f.wrap = false
		}
	case "flex-flow":
		rest := value
		for word in strings.fields_iterator(&rest) {
			if d, ok := parse_flex_direction(word); ok {
				f.direction = d
			} else if word == "wrap" || word == "wrap-reverse" {
				f.wrap = true
			} else if word == "nowrap" {
				f.wrap = false
			}
		}
	case "justify-content":
		switch value {
		case "flex-start", "start", "left", "normal", "initial":
			f.justify = .Start
		case "flex-end", "end", "right":
			f.justify = .End
		case "center":
			f.justify = .Center
		case "space-between":
			f.justify = .Space_Between
		case "space-around":
			f.justify = .Space_Around
		case "space-evenly":
			f.justify = .Space_Evenly
		}
	case "align-items":
		if a, ok := parse_align(value); ok {
			f.align_items = a
		}
	case "align-self":
		if value == "auto" || value == "initial" {
			f.align_self = .Auto
		} else if a, ok := parse_align(value); ok {
			f.align_self = Align_Self(int(a) + 1)
		}
	case "gap":
		// one value for both, or "row column"
		words := split_outside_parens(value, context.temp_allocator)
		if len(words) >= 1 {
			if row, ok := parse_length(words[0], false); ok {
				f.row_gap = row
				f.column_gap = row
			}
		}
		if len(words) >= 2 {
			if column, ok := parse_length(words[1], false); ok {
				f.column_gap = column
			}
		}
	case "row-gap":
		f.row_gap = parse_length(value, false) or_else f.row_gap
	case "column-gap":
		f.column_gap = parse_length(value, false) or_else f.column_gap
	case "flex-grow":
		f.grow = max(strconv.parse_f32(value) or_else f.grow, 0)
	case "flex-shrink":
		f.shrink = max(strconv.parse_f32(value) or_else f.shrink, 0)
	case "flex-basis":
		if value == "content" {
			f.basis = AUTO
		} else {
			f.basis = parse_length(value, true) or_else f.basis
		}
	case "flex":
		parse_flex_shorthand(f, value)
	}
}

// flex: none | auto | <grow> [<shrink>] [<basis>] | <basis>
@(private)
parse_flex_shorthand :: proc(f: ^Flex, value: string) {
	switch value {
	case "none":
		f.grow, f.shrink, f.basis = 0, 0, AUTO
		return
	case "auto":
		f.grow, f.shrink, f.basis = 1, 1, AUTO
		return
	case "initial":
		f.grow, f.shrink, f.basis = 0, 1, AUTO
		return
	}
	// a number alone means "<grow> 1 0%"
	grow, shrink: f32 = 1, 1
	basis := px(0)
	numbers := 0
	rest := value
	for word in strings.fields_iterator(&rest) {
		if n, ok := strconv.parse_f32(word); ok && numbers < 2 {
			if numbers == 0 {
				grow = n
			} else {
				shrink = n
			}
			numbers += 1
		} else if length, ok := parse_length(word, true); ok {
			basis = length
		}
	}
	f.grow, f.shrink, f.basis = max(grow, 0), max(shrink, 0), basis
}

@(private)
parse_flex_direction :: proc(value: string) -> (Flex_Direction, bool) {
	switch value {
	case "row":
		return .Row, true
	case "row-reverse":
		return .Row_Reverse, true
	case "column":
		return .Column, true
	case "column-reverse":
		return .Column_Reverse, true
	}
	return .Row, false
}

@(private)
parse_align :: proc(value: string) -> (Align, bool) {
	switch value {
	case "stretch", "normal":
		return .Stretch, true
	case "flex-start", "start", "self-start", "baseline", "first baseline":
		return .Start, true
	case "flex-end", "end", "self-end", "last baseline":
		return .End, true
	case "center":
		return .Center, true
	}
	return .Stretch, false
}
