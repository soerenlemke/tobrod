package svg

import "core:math"

// A stroke (the line along a path) as polygons the rasterizer can fill:
//
// - every segment of the path becomes a rectangle of the stroke's width,
// - where two segments meet, the gap on the outer side is filled (the join):
//   bevel with a triangle, miter with the pointed corner (if it isn't longer
//   than miterlimit times the width, else bevel), round with a circle,
// - an open subpath gets its ends (the cap): butt (nothing), square (half the
//   width further), round (a circle).
//
// All pieces turn the same way (counter-clockwise), so with the nonzero rule
// overlapping pieces simply add up instead of cutting holes into each other.
// The stroke is computed in pixels, after the transform; its width is scaled
// by the transform's average scale.

Line_Cap :: enum {
	Butt,
	Round,
	Square,
}

Line_Join :: enum {
	Miter,
	Round,
	Bevel,
}

Stroke_Style :: struct {
	width:       f32, // in pixels
	cap:         Line_Cap,
	join:        Line_Join,
	miter_limit: f32,
}

stroke_outline :: proc(polygons: []Polygon, closed: []bool, style: Stroke_Style) -> [dynamic]Polygon {
	result := make([dynamic]Polygon, context.temp_allocator)
	half := style.width / 2
	if half <= 0 {
		return result
	}
	for poly, index in polygons {
		points := without_repeats(poly[:])
		is_closed := index < len(closed) && closed[index]
		if is_closed && len(points) > 1 && points[0] == points[len(points) - 1] {
			points = points[:len(points) - 1]
		}
		n := len(points)
		if n == 0 {
			continue
		}
		if n == 1 {
			// a single point: only round and square caps draw something
			add_cap_dot(&result, points[0], half, style.cap)
			continue
		}
		segments := n if is_closed else n - 1
		for i in 0 ..< segments {
			add_quad(&result, points[i], points[(i + 1) % n], half)
		}
		// joins at the inner points (and all points of a closed path)
		for i in 0 ..< n {
			if !is_closed && (i == 0 || i == n - 1) {
				continue
			}
			prev, next := points[(i + n - 1) % n], points[(i + 1) % n]
			add_join(&result, prev, points[i], next, half, style)
		}
		if !is_closed {
			add_cap(&result, points[1], points[0], half, style.cap)
			add_cap(&result, points[n - 2], points[n - 1], half, style.cap)
		}
	}
	return result
}

// Points without a point equal to the one before (they have no direction).
@(private)
without_repeats :: proc(points: []Point) -> []Point {
	result := make([dynamic]Point, 0, len(points), context.temp_allocator)
	for p in points {
		if len(result) == 0 || distance(result[len(result) - 1], p) > 0.001 {
			append(&result, p)
		}
	}
	return result[:]
}

// The unit vector at a right angle to a -> b (to its left on screen).
@(private)
normal :: proc(a, b: Point) -> Point {
	d := b - a
	length := math.sqrt(d.x * d.x + d.y * d.y)
	return {-d.y / length, d.x / length}
}

@(private)
add_quad :: proc(result: ^[dynamic]Polygon, a, b: Point, half: f32) {
	n := normal(a, b) * half
	add_polygon(result, {a + n, b + n, b - n, a - n})
}

@(private)
add_join :: proc(result: ^[dynamic]Polygon, prev, p, next: Point, half: f32, style: Stroke_Style) {
	n1, n2 := normal(prev, p), normal(p, next)
	// which side is the outer one: the side the path turns away from
	d1, d2 := p - prev, next - p
	turn := d1.x * d2.y - d1.y * d2.x
	if abs(turn) < 1e-6 && (d1.x * d2.x + d1.y * d2.y) > 0 {
		return // straight on: nothing to fill
	}
	side: f32 = -1 if turn > 0 else 1
	a, b := p + n1 * half * side, p + n2 * half * side
	switch style.join {
	case .Round:
		add_circle(result, p, half)
	case .Bevel:
		add_polygon(result, {p, a, b})
	case .Miter:
		// the corner where the two outer edges meet
		cos_theta := n1.x * n2.x + n1.y * n2.y // angle between the segments' normals
		miter_length := 1 / math.sqrt(max((1 + cos_theta) / 2, 1e-6)) // in half widths
		if miter_length <= style.miter_limit {
			bisector := n1 + n2
			length := math.sqrt(bisector.x * bisector.x + bisector.y * bisector.y)
			if length > 1e-6 {
				tip := p + bisector / length * half * miter_length * side
				add_polygon(result, {p, a, tip, b})
				return
			}
		}
		add_polygon(result, {p, a, b})
	}
}

// The cap at the end `end` of a segment coming from `from`.
@(private)
add_cap :: proc(result: ^[dynamic]Polygon, from, end: Point, half: f32, cap: Line_Cap) {
	switch cap {
	case .Butt:
	case .Round:
		add_circle(result, end, half)
	case .Square:
		d := end - from
		length := math.sqrt(d.x * d.x + d.y * d.y)
		out := d / length * half
		n := normal(from, end) * half
		add_polygon(result, {end + n, end + n + out, end - n + out, end - n})
	}
}

@(private)
add_cap_dot :: proc(result: ^[dynamic]Polygon, p: Point, half: f32, cap: Line_Cap) {
	switch cap {
	case .Butt:
	case .Round:
		add_circle(result, p, half)
	case .Square:
		add_polygon(result, {p + {-half, -half}, p + {half, -half}, p + {half, half}, p + {-half, half}})
	}
}

@(private)
add_circle :: proc(result: ^[dynamic]Polygon, center: Point, radius: f32) {
	steps := clamp(int(radius * 2), 8, 64)
	circle := make(Polygon, 0, steps, context.temp_allocator)
	for i in 0 ..< steps {
		a := 2 * math.PI * f32(i) / f32(steps)
		append(&circle, center + Point{math.cos(a), math.sin(a)} * radius)
	}
	add_polygon_list(result, circle)
}

@(private)
add_polygon :: proc(result: ^[dynamic]Polygon, points: []Point) {
	poly := make(Polygon, 0, len(points), context.temp_allocator)
	append(&poly, ..points)
	add_polygon_list(result, poly)
}

// Adds a polygon turning the same way as all others (positive area).
@(private)
add_polygon_list :: proc(result: ^[dynamic]Polygon, poly: Polygon) {
	area: f32 = 0
	for i in 0 ..< len(poly) {
		a, b := poly[i], poly[(i + 1) % len(poly)]
		area += a.x * b.y - b.x * a.y
	}
	if area < 0 {
		for i in 0 ..< len(poly) / 2 {
			poly[i], poly[len(poly) - 1 - i] = poly[len(poly) - 1 - i], poly[i]
		}
	}
	append(result, poly)
}
