package dom

import "core:strconv"
import "core:strings"

// calc(): arithmetic on lengths, like calc(100% - 2em) or calc(3 * 1rem).
//
// Lengths in different units can only be added once the layout knows what
// em and % are, so a calc() is kept as a sum with one term per unit
// (Length.calc) and resolve_length adds them up. Multiplying and dividing
// is only allowed by plain numbers (that is the rule in CSS too), so every
// calc() of lengths reduces to such a sum.
//
// Grammar (a small recursive descent parser):
//   sum     = product (("+" | "-") product)*   + and - need spaces around them
//   product = operand (("*" | "/") operand)*
//   operand = number | number unit | "(" sum ")" | "calc(" sum ")"

// A value while calculating: a plain number or a length (the sum of terms).
@(private)
Calc_Value :: struct {
	terms:     [Length_Unit]f32,
	number:    f32,
	is_number: bool,
}

@(private)
Calc_Parser :: struct {
	s:   string,
	pos: int,
}

// Parses "calc(...)". A result in one unit becomes a normal length
// (calc(1120px - 1px) = 1119px), only mixed units need .Calc.
parse_calc :: proc(value: string) -> (length: Length, ok: bool) {
	if !strings.has_prefix(value, "calc(") {
		return
	}
	p := Calc_Parser{s = value, pos = len("calc(")}
	v := calc_sum(&p) or_return
	calc_skip_spaces(&p)
	if !calc_take(&p, ')') || p.pos != len(p.s) || v.is_number {
		return
	}
	return length_from_terms(v.terms), true
}

// true if the length depends on the size of the containing block.
has_percent :: proc(length: Length) -> bool {
	return length.unit == .Percent || (length.unit == .Calc && length.calc[.Percent] != 0)
}

// true for lengths that are 0 (calc() counts as not 0, we only know later).
is_zero :: proc(length: Length) -> bool {
	return length.unit != .Auto && length.unit != .Calc && length.value == 0
}

@(private)
length_from_terms :: proc(terms: [Length_Unit]f32) -> Length {
	result := px(0)
	count := 0
	for value, unit in terms {
		if value != 0 {
			result = {unit = unit, value = value}
			count += 1
		}
	}
	if count > 1 {
		return {unit = .Calc, calc = terms}
	}
	return result
}

@(private)
calc_sum :: proc(p: ^Calc_Parser) -> (result: Calc_Value, ok: bool) {
	result = calc_product(p) or_return
	for {
		before := p.pos
		calc_skip_spaces(p)
		if p.pos == len(p.s) || (p.s[p.pos] != '+' && p.s[p.pos] != '-') {
			p.pos = before
			return result, true
		}
		// "100% -2em" or "100%-2em" are not a subtraction in CSS
		sign: f32 = 1 if p.s[p.pos] == '+' else -1
		if before == p.pos || p.pos + 1 == len(p.s) || !is_calc_space(p.s[p.pos + 1]) {
			return {}, false
		}
		p.pos += 1
		right := calc_product(p) or_return
		if right.is_number != result.is_number {
			return {}, false // 1 + 2px makes no sense
		}
		result.number += sign * right.number
		for unit in Length_Unit {
			result.terms[unit] += sign * right.terms[unit]
		}
	}
}

@(private)
calc_product :: proc(p: ^Calc_Parser) -> (result: Calc_Value, ok: bool) {
	result = calc_operand(p) or_return
	for {
		before := p.pos
		calc_skip_spaces(p)
		if p.pos == len(p.s) || (p.s[p.pos] != '*' && p.s[p.pos] != '/') {
			p.pos = before
			return result, true
		}
		divide := p.s[p.pos] == '/'
		p.pos += 1
		right := calc_operand(p) or_return
		switch {
		case divide:
			// only by a number, and not by 0
			if !right.is_number || right.number == 0 {
				return {}, false
			}
			result = calc_scale(result, 1 / right.number)
		case right.is_number:
			result = calc_scale(result, right.number)
		case result.is_number:
			result = calc_scale(right, result.number)
		case:
			return {}, false // 2px * 3px is an area, not a length
		}
	}
}

@(private)
calc_scale :: proc(v: Calc_Value, factor: f32) -> Calc_Value {
	v := v
	v.number *= factor
	for unit in Length_Unit {
		v.terms[unit] *= factor
	}
	return v
}

@(private)
calc_operand :: proc(p: ^Calc_Parser) -> (result: Calc_Value, ok: bool) {
	calc_skip_spaces(p)
	nested := strings.has_prefix(p.s[p.pos:], "calc(")
	if nested || calc_take(p, '(') {
		if nested {
			p.pos += len("calc(")
		}
		result = calc_sum(p) or_return
		calc_skip_spaces(p)
		return result, calc_take(p, ')')
	}
	// a number with its unit ends at a space, a bracket or * and /
	start := p.pos
	for p.pos < len(p.s) && !is_calc_space(p.s[p.pos]) && !strings.contains_rune("()*/", rune(p.s[p.pos])) {
		p.pos += 1
	}
	number, unit := split_number(p.s[start:p.pos])
	n := strconv.parse_f32(number) or_return
	if unit == "" {
		return {number = n, is_number = true}, true
	}
	length := length_with_unit(n, unit) or_return
	result.terms[length.unit] = length.value
	return result, true
}

@(private)
calc_skip_spaces :: proc(p: ^Calc_Parser) {
	for p.pos < len(p.s) && is_calc_space(p.s[p.pos]) {
		p.pos += 1
	}
}

@(private)
is_calc_space :: proc(c: byte) -> bool {
	return c == ' ' || c == '\t' || c == '\n' || c == '\r'
}

@(private)
calc_take :: proc(p: ^Calc_Parser, c: byte) -> bool {
	if p.pos < len(p.s) && p.s[p.pos] == c {
		p.pos += 1
		return true
	}
	return false
}
