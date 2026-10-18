package svg

import "core:math"
import "core:strconv"

// Path data ("M10 10 L20 20 C ... Z") into polygons: every subpath becomes a
// list of points in pixels (the transform is already applied). Curves and
// arcs are flattened into short lines here, after the transform, so they get
// as many segments as their size on screen needs.

Polygon :: [dynamic]Point

// Reads numbers and flags out of path data. SVG lets them run together:
// "1.5.5-2" is 1.5, .5 and -2; arc flags can be single digits without spaces.
Scanner :: struct {
	s:   string,
	pos: int,
}

@(private)
skip_separators :: proc(sc: ^Scanner) {
	for sc.pos < len(sc.s) {
		switch sc.s[sc.pos] {
		case ' ', '\t', '\n', '\r', ',':
			sc.pos += 1
		case:
			return
		}
	}
}

scan_number :: proc(sc: ^Scanner) -> (n: f32, ok: bool) {
	skip_separators(sc)
	start := sc.pos
	i := sc.pos
	if i < len(sc.s) && (sc.s[i] == '-' || sc.s[i] == '+') {
		i += 1
	}
	digits, dot := false, false
	for i < len(sc.s) {
		c := sc.s[i]
		if c >= '0' && c <= '9' {
			digits = true
		} else if c == '.' && !dot {
			dot = true
		} else {
			break
		}
		i += 1
	}
	if !digits {
		return 0, false
	}
	// an exponent, but not the "e" of a following command (there is none: e
	// is not a path command)
	if i < len(sc.s) && (sc.s[i] == 'e' || sc.s[i] == 'E') {
		j := i + 1
		if j < len(sc.s) && (sc.s[j] == '-' || sc.s[j] == '+') {
			j += 1
		}
		if j < len(sc.s) && sc.s[j] >= '0' && sc.s[j] <= '9' {
			i = j
			for i < len(sc.s) && sc.s[i] >= '0' && sc.s[i] <= '9' {
				i += 1
			}
		}
	}
	n, ok = strconv.parse_f32(sc.s[start:i])
	if ok {
		sc.pos = i
	}
	return
}

// An arc flag: a single 0 or 1.
@(private)
scan_flag :: proc(sc: ^Scanner) -> (flag: bool, ok: bool) {
	skip_separators(sc)
	if sc.pos < len(sc.s) && (sc.s[sc.pos] == '0' || sc.s[sc.pos] == '1') {
		sc.pos += 1
		return sc.s[sc.pos - 1] == '1', true
	}
	return false, false
}

// A path builder: collects subpaths in pixels.
Path_Builder :: struct {
	m:        Matrix,
	scale:    f32, // of m: how many pixels one unit is
	polygons: [dynamic]Polygon,
	closed:   [dynamic]bool, // per polygon: ended with Z (for strokes: a join instead of two ends)
	current:  ^Polygon,
}

path_builder :: proc(m: Matrix, allocator := context.temp_allocator) -> Path_Builder {
	return {m = m, scale = scale_of(m), polygons = make([dynamic]Polygon, allocator), closed = make([dynamic]bool, allocator)}
}

move_to :: proc(pb: ^Path_Builder, p: Point) {
	append(&pb.polygons, make(Polygon, pb.polygons.allocator))
	append(&pb.closed, false)
	pb.current = &pb.polygons[len(pb.polygons) - 1]
	append(pb.current, apply(pb.m, p))
}

line_to :: proc(pb: ^Path_Builder, p: Point) {
	if pb.current == nil {
		move_to(pb, p)
		return
	}
	append(pb.current, apply(pb.m, p))
}

// A cubic Bézier curve from the current point; flattened in pixels.
cubic_to :: proc(pb: ^Path_Builder, p0, c1, c2, p: Point) {
	a, b, c, d := apply(pb.m, p0), apply(pb.m, c1), apply(pb.m, c2), apply(pb.m, p)
	length := distance(a, b) + distance(b, c) + distance(c, d) // longer than the curve
	steps := clamp(int(length / 2), 2, 200)
	for i in 1 ..= steps {
		t := f32(i) / f32(steps)
		u := 1 - t
		point := u * u * u * a + 3 * u * u * t * b + 3 * u * t * t * c + t * t * t * d
		append(pb.current, point)
	}
}

quad_to :: proc(pb: ^Path_Builder, p0, c, p: Point) {
	// a quadratic curve is a cubic one with these control points
	cubic_to(pb, p0, p0 + 2.0 / 3.0 * (c - p0), p + 2.0 / 3.0 * (c - p), p)
}

// An elliptical arc in SVG's form (from p0 to p, radii, rotation, flags).
arc_to :: proc(pb: ^Path_Builder, p0: Point, rx, ry, angle: f32, large, sweep: bool, p: Point) {
	rx, ry := abs(rx), abs(ry)
	if rx == 0 || ry == 0 || p0 == p {
		line_to(pb, p)
		return
	}
	// the conversion to center form, as in the SVG spec (appendix F.6.5)
	phi := math.to_radians(angle)
	cos, sin := math.cos(phi), math.sin(phi)
	dx, dy := (p0.x - p.x) / 2, (p0.y - p.y) / 2
	x1 := cos * dx + sin * dy
	y1 := -sin * dx + cos * dy
	// radii too small for the two points: scaled up
	lambda := (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
	if lambda > 1 {
		s := math.sqrt(lambda)
		rx, ry = rx * s, ry * s
	}
	num := rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
	den := rx * rx * y1 * y1 + ry * ry * x1 * x1
	k := math.sqrt(max(num / den, 0))
	if large == sweep {
		k = -k
	}
	cx1, cy1 := k * rx * y1 / ry, -k * ry * x1 / rx
	cx := cos * cx1 - sin * cy1 + (p0.x + p.x) / 2
	cy := sin * cx1 + cos * cy1 + (p0.y + p.y) / 2

	angle_of :: proc(ux, uy, vx, vy: f32) -> f32 {
		return math.atan2(ux * vy - uy * vx, ux * vx + uy * vy)
	}
	theta := angle_of(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
	delta := angle_of((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
	if !sweep && delta > 0 {
		delta -= 2 * math.PI
	} else if sweep && delta < 0 {
		delta += 2 * math.PI
	}

	steps := clamp(int(abs(delta) * max(rx, ry) * pb.scale / 2), 4, 200)
	for i in 1 ..= steps {
		t := theta + delta * f32(i) / f32(steps)
		x := rx * math.cos(t)
		y := ry * math.sin(t)
		line_to(pb, {cos * x - sin * y + cx, sin * x + cos * y + cy})
	}
}

close_path :: proc(pb: ^Path_Builder) {
	if pb.current != nil && len(pb.current) > 0 {
		first := pb.current[0]
		pb.closed[len(pb.closed) - 1] = true
		pb.current = nil
		// the next command starts where this subpath started
		append(&pb.polygons, make(Polygon, pb.polygons.allocator))
		append(&pb.closed, false)
		pb.current = &pb.polygons[len(pb.polygons) - 1]
		append(pb.current, first)
	}
}

@(private)
distance :: proc(a, b: Point) -> f32 {
	return math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y))
}

// The "d" attribute of a path. Stops at the first error, like browsers:
// what was read up to there is drawn (and ok is false).
parse_path :: proc(pb: ^Path_Builder, d: string) -> (ok: bool) {
	sc := Scanner{s = d}
	command: u8 = 0
	current, start: Point // in user units
	last_control: Point // of the previous C/S or Q/T, for the smooth ones
	previous: u8 = 0

	for {
		skip_separators(&sc)
		if sc.pos >= len(sc.s) {
			return true
		}
		c := sc.s[sc.pos]
		if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') {
			command = c
			sc.pos += 1
		} else if command == 0 {
			return
		}
		// after M, more coordinate pairs are lines
		relative := command >= 'a'
		base := current if relative else Point{}

		switch command | 0x20 { // lowercase
		case 'm':
			p := read_point(&sc) or_return
			current = base + p
			start = current
			move_to(pb, current)
			command = 'l' if relative else 'L'
		case 'l':
			p := read_point(&sc) or_return
			current = base + p
			line_to(pb, current)
		case 'h':
			x := scan_number(&sc) or_return
			current.x = (current.x if relative else 0) + x
			line_to(pb, current)
		case 'v':
			y := scan_number(&sc) or_return
			current.y = (current.y if relative else 0) + y
			line_to(pb, current)
		case 'c':
			c1 := read_point(&sc) or_return
			c2 := read_point(&sc) or_return
			p := read_point(&sc) or_return
			ensure_started(pb, current)
			cubic_to(pb, current, base + c1, base + c2, base + p)
			last_control = base + c2
			current = base + p
		case 's':
			c2 := read_point(&sc) or_return
			p := read_point(&sc) or_return
			c1 := current
			if previous | 0x20 == 'c' || previous | 0x20 == 's' {
				c1 = 2 * current - last_control // the mirrored control point
			}
			ensure_started(pb, current)
			cubic_to(pb, current, c1, base + c2, base + p)
			last_control = base + c2
			current = base + p
		case 'q':
			c1 := read_point(&sc) or_return
			p := read_point(&sc) or_return
			ensure_started(pb, current)
			quad_to(pb, current, base + c1, base + p)
			last_control = base + c1
			current = base + p
		case 't':
			p := read_point(&sc) or_return
			c1 := current
			if previous | 0x20 == 'q' || previous | 0x20 == 't' {
				c1 = 2 * current - last_control
			}
			ensure_started(pb, current)
			quad_to(pb, current, c1, base + p)
			last_control = c1
			current = base + p
		case 'a':
			rx := scan_number(&sc) or_return
			ry := scan_number(&sc) or_return
			angle := scan_number(&sc) or_return
			large := scan_flag(&sc) or_return
			sweep := scan_flag(&sc) or_return
			p := read_point(&sc) or_return
			ensure_started(pb, current)
			arc_to(pb, current, rx, ry, angle, large, sweep, base + p)
			current = base + p
		case 'z':
			close_path(pb)
			current = start
			previous = command
			command = 0 // Z takes no numbers: a number after it is an error
		case:
			return // unknown command
		}
		previous = command
	}
}

@(private)
read_point :: proc(sc: ^Scanner) -> (p: Point, ok: bool) {
	p.x = scan_number(sc) or_return
	p.y = scan_number(sc) or_return
	return p, true
}

// A curve right after Z (or at the very start) needs a current subpath.
@(private)
ensure_started :: proc(pb: ^Path_Builder, p: Point) {
	if pb.current == nil {
		move_to(pb, p)
	}
}
