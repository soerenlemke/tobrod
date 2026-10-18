package svg

import "core:math"
import "core:strings"

// An affine transform as in SVG's matrix(a b c d e f):
//   x' = a*x + c*y + e
//   y' = b*x + d*y + f
Matrix :: [6]f32

IDENTITY :: Matrix{1, 0, 0, 1, 0, 0}

Point :: [2]f32

apply :: proc(m: Matrix, p: Point) -> Point {
	return {m[0] * p.x + m[2] * p.y + m[4], m[1] * p.x + m[3] * p.y + m[5]}
}

// m then n: first m is applied to a point, then n.
multiply :: proc(n, m: Matrix) -> Matrix {
	return {
		n[0] * m[0] + n[2] * m[1],
		n[1] * m[0] + n[3] * m[1],
		n[0] * m[2] + n[2] * m[3],
		n[1] * m[2] + n[3] * m[3],
		n[0] * m[4] + n[2] * m[5] + n[4],
		n[1] * m[4] + n[3] * m[5] + n[5],
	}
}

// How much the transform enlarges lengths (on average): for flattening
// curves into enough line segments.
scale_of :: proc(m: Matrix) -> f32 {
	return math.sqrt(abs(m[0] * m[3] - m[1] * m[2]))
}

// The transform attribute: a list like "translate(10 20) rotate(45) scale(2)".
// The functions are applied right to left, like nested groups.
parse_transform :: proc(value: string) -> (m: Matrix, ok: bool) {
	m = IDENTITY
	rest := strings.trim_space(value)
	for len(rest) > 0 {
		open := strings.index_byte(rest, '(')
		close := strings.index_byte(rest, ')')
		if open < 0 || close < open {
			return IDENTITY, false
		}
		name := strings.trim(rest[:open], " \t\n\r,")
		args := numbers_of(rest[open + 1:close])
		rest = strings.trim_left(rest[close + 1:], " \t\n\r,")

		t := IDENTITY
		switch name {
		case "matrix":
			if len(args) != 6 {
				return IDENTITY, false
			}
			t = {args[0], args[1], args[2], args[3], args[4], args[5]}
		case "translate":
			if len(args) == 0 {
				return IDENTITY, false
			}
			t[4] = args[0]
			if len(args) > 1 {
				t[5] = args[1]
			}
		case "scale":
			if len(args) == 0 {
				return IDENTITY, false
			}
			t[0], t[3] = args[0], args[0]
			if len(args) > 1 {
				t[3] = args[1]
			}
		case "rotate":
			if len(args) == 0 {
				return IDENTITY, false
			}
			a := math.to_radians(args[0])
			cos, sin := math.cos(a), math.sin(a)
			t = {cos, sin, -sin, cos, 0, 0}
			if len(args) == 3 {
				// rotate around (cx, cy)
				cx, cy := args[1], args[2]
				t = multiply(Matrix{1, 0, 0, 1, cx, cy}, multiply(t, Matrix{1, 0, 0, 1, -cx, -cy}))
			}
		case "skewX":
			if len(args) == 0 {
				return IDENTITY, false
			}
			t[2] = math.tan(math.to_radians(args[0]))
		case "skewY":
			if len(args) == 0 {
				return IDENTITY, false
			}
			t[1] = math.tan(math.to_radians(args[0]))
		case:
			return IDENTITY, false
		}
		m = multiply(m, t)
	}
	return m, true
}

// All numbers in a list like "1,2 3-4.5e1": for transforms and points.
numbers_of :: proc(s: string) -> []f32 {
	result := make([dynamic]f32, context.temp_allocator)
	sc := Scanner{s = s}
	for {
		n, ok := scan_number(&sc)
		if !ok {
			break
		}
		append(&result, n)
	}
	return result[:]
}
