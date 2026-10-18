package dom

import "core:math"
import "core:strconv"
import "core:strings"

// transform: a list of 2D functions, applied right to left like nested
// groups (translate(10px) rotate(45deg) rotates first, then moves). The
// layout turns them into a matrix once the element's size is known, because
// percentages in translate() refer to the element's own border box. 3D
// functions are reduced to 2D: translateZ and perspective are dropped,
// rotateX/rotateY count as a flip (scale -1) from 90 to 270 degrees.
// transform-origin is where scale and rotate are centered (50% 50% by default).
// Not inherited.
MAX_TRANSFORMS :: 8

Transform :: struct {
	list:   [MAX_TRANSFORMS]Transform_Fn,
	count:  int,
	origin: Maybe([2]Length), // nil = 50% 50%
}

Transform_Fn :: struct {
	kind: Transform_Kind,
	x, y: Length, // translate
	a:    [6]f32, // scale (a[0], a[1]), rotate (a[0] in radians), skew (radians), matrix
}

Transform_Kind :: enum {
	Translate,
	Scale,
	Rotate,
	Skew,
	Matrix,
}

@(private)
apply_transform_declaration :: proc(style: ^Style, property, value: string) {
	v := strings.to_lower(strings.trim_space(value), context.temp_allocator)
	switch property {
	case "transform", "-webkit-transform":
		if v == "none" || v == "initial" || v == "unset" {
			style.transform.count = 0
		} else if t, ok := parse_transform_list(v); ok {
			t.origin = style.transform.origin
			style.transform = t
		}
	case "transform-origin", "-webkit-transform-origin":
		words := strings.fields(v, context.temp_allocator)
		if len(words) == 3 {
			words = words[:2] // the z offset
		}
		if v == "initial" || v == "unset" {
			style.transform.origin = nil
		} else if position, ok := parse_layer_position(words); ok {
			style.transform.origin = position
		}
	}
}

@(private)
parse_transform_list :: proc(value: string) -> (t: Transform, ok: bool) {
	rest := value
	for len(strings.trim_space(rest)) > 0 {
		rest = strings.trim_left(rest, " ")
		open := strings.index_byte(rest, '(')
		if open < 0 {
			return
		}
		// the matching parenthesis (calc() can be nested inside)
		depth, close := 0, -1
		for i in open ..< len(rest) {
			if rest[i] == '(' {
				depth += 1
			} else if rest[i] == ')' {
				depth -= 1
				if depth == 0 {
					close = i
					break
				}
			}
		}
		if close < 0 {
			return
		}
		name := strings.to_lower(strings.trim_space(rest[:open]), context.temp_allocator)
		args := transform_args(rest[open + 1:close])
		rest = rest[close + 1:]
		fn, keep := parse_transform_fn(name, args) or_return
		if keep && t.count < MAX_TRANSFORMS {
			t.list[t.count] = fn
			t.count += 1
		}
	}
	return t, true
}

// The arguments of a function, split at commas (or spaces in old syntax)
// outside of parentheses.
@(private)
transform_args :: proc(s: string) -> []string {
	spaced, _ := strings.replace_all(s, ",", " ", context.temp_allocator)
	return split_outside_parens(spaced, context.temp_allocator)
}

// One function; keep is false for the ones without an effect in 2D.
@(private)
parse_transform_fn :: proc(name: string, args: []string) -> (fn: Transform_Fn, keep, ok: bool) {
	length :: proc(s: string) -> (l: Length, ok: bool) {
		return parse_length(s, false)
	}
	number :: proc(s: string) -> (n: f32, ok: bool) {
		if strings.has_suffix(s, "%") {
			n := strconv.parse_f32(s[:len(s) - 1]) or_return
			return n / 100, true
		}
		return strconv.parse_f32(s)
	}
	n := len(args)
	switch name {
	case "translate", "translate3d":
		if n < 1 {
			return
		}
		fn.kind = .Translate
		fn.x = length(args[0]) or_return
		if n >= 2 {
			fn.y = length(args[1]) or_return
		}
	case "translatex":
		fn.kind = .Translate
		fn.x = length(args[0] if n > 0 else "") or_return
	case "translatey":
		fn.kind = .Translate
		fn.y = length(args[0] if n > 0 else "") or_return
	case "translatez", "perspective":
		return {}, false, true
	case "scale", "scale3d":
		if n < 1 {
			return
		}
		fn.kind = .Scale
		fn.a[0] = number(args[0]) or_return
		fn.a[1] = fn.a[0]
		if n >= 2 {
			fn.a[1] = number(args[1]) or_return
		}
	case "scalex":
		fn.kind = .Scale
		fn.a[0] = number(args[0] if n > 0 else "") or_return
		fn.a[1] = 1
	case "scaley":
		fn.kind = .Scale
		fn.a[0] = 1
		fn.a[1] = number(args[0] if n > 0 else "") or_return
	case "scalez":
		return {}, false, true
	case "rotate", "rotatez":
		fn.kind = .Rotate
		fn.a[0] = parse_angle(args[0] if n > 0 else "") or_return
	case "rotatex", "rotatey":
		// seen from the front: the element is mirrored when turned past 90 degrees
		angle := parse_angle(args[0] if n > 0 else "") or_return
		cos := math.cos(angle)
		fn.kind = .Scale
		fn.a[0], fn.a[1] = 1, 1
		if name == "rotatex" {
			fn.a[1] = cos
		} else {
			fn.a[0] = cos
		}
	case "rotate3d":
		return {}, false, true
	case "skew", "skewx", "skewy":
		fn.kind = .Skew
		if name == "skewy" {
			fn.a[1] = parse_angle(args[0] if n > 0 else "") or_return
		} else {
			fn.a[0] = parse_angle(args[0] if n > 0 else "") or_return
			if name == "skew" && n >= 2 {
				fn.a[1] = parse_angle(args[1]) or_return
			}
		}
	case "matrix":
		if n != 6 {
			return
		}
		fn.kind = .Matrix
		for i in 0 ..< 6 {
			fn.a[i] = strconv.parse_f32(args[i]) or_return
		}
	case:
		return // unknown: the whole transform is invalid
	}
	return fn, true, true
}

// deg, rad, turn, grad (0 without a unit), in radians.
@(private)
parse_angle :: proc(s: string) -> (radians: f32, ok: bool) {
	if s == "0" {
		return 0, true
	}
	number, unit := split_number(s)
	v := strconv.parse_f32(number) or_return
	switch unit {
	case "deg":
		return v * math.PI / 180, true
	case "rad":
		return v, true
	case "turn":
		return v * 2 * math.PI, true
	case "grad":
		return v * math.PI / 200, true
	}
	return 0, false
}
