package ui

import "core:math"
import "../dom"
import "../layout"
import rl "vendor:raylib"

// A box with rounded corners (border-radius). raylib can round a rectangle,
// but only with the same radius on all corners and no borders of different
// widths, so we build the shape ourselves: its outline as points, with an
// arc of ARC_STEPS segments per corner (a corner without a radius gets the
// same number of points, all on the corner). The background fills the
// outline with triangles from the middle (the shape is convex); the border
// is a strip between the outline and the inner edge of the border.

@(private)
ARC_STEPS :: 8

@(private)
OUTLINE_POINTS :: 4 * (ARC_STEPS + 1)

@(private)
draw_rounded_box :: proc(x, y: f32, box: layout.Box) {
	w, h := box.width, box.height
	outer := outline(x, y, w, h, box.radius, {})
	if box.color[3] > 0 {
		middle := rl.Vector2{x + w / 2, y + h / 2}
		for i in 0 ..< OUTLINE_POINTS {
			draw_triangle_any_order(middle, outer[i], outer[(i + 1) % OUTLINE_POINTS], rl.Color(box.color))
		}
	}

	border := box.border
	if border[.Top] == 0 && border[.Right] == 0 && border[.Bottom] == 0 && border[.Left] == 0 {
		return
	}
	inner := outline(x + border[.Left], y + border[.Top], w - border[.Left] - border[.Right], h - border[.Top] - border[.Bottom], box.radius, border)
	for i in 0 ..< OUTLINE_POINTS {
		next := (i + 1) % OUTLINE_POINTS
		color := rl.Color(box.border_color[side_of_segment(i)])
		draw_triangle_any_order(outer[i], inner[i], outer[next], color)
		draw_triangle_any_order(inner[i], inner[next], outer[next], color)
	}
}

// The outline of a rounded rectangle, clockwise from the left end of the
// top-left arc. With border widths, it is the inner edge of the border: the
// corner radii get smaller by the width of the sides next to them (and so
// become elliptical when those differ, like in CSS).
@(private)
outline :: proc(x, y, w, h: f32, radius: [dom.Corner]f32, border: [dom.Edge]f32) -> (points: [OUTLINE_POINTS]rl.Vector2) {
	Arc :: struct {
		cx, cy, rx, ry, start: f32, // start angle in degrees; y points down
	}
	r := radius
	arcs := [dom.Corner]Arc {
		.Top_Left     = {x + max(r[.Top_Left] - border[.Left], 0), y + max(r[.Top_Left] - border[.Top], 0), max(r[.Top_Left] - border[.Left], 0), max(r[.Top_Left] - border[.Top], 0), 180},
		.Top_Right    = {x + w - max(r[.Top_Right] - border[.Right], 0), y + max(r[.Top_Right] - border[.Top], 0), max(r[.Top_Right] - border[.Right], 0), max(r[.Top_Right] - border[.Top], 0), 270},
		.Bottom_Right = {x + w - max(r[.Bottom_Right] - border[.Right], 0), y + h - max(r[.Bottom_Right] - border[.Bottom], 0), max(r[.Bottom_Right] - border[.Right], 0), max(r[.Bottom_Right] - border[.Bottom], 0), 0},
		.Bottom_Left  = {x + max(r[.Bottom_Left] - border[.Left], 0), y + h - max(r[.Bottom_Left] - border[.Bottom], 0), max(r[.Bottom_Left] - border[.Left], 0), max(r[.Bottom_Left] - border[.Bottom], 0), 90},
	}
	n := 0
	for arc in arcs {
		for step in 0 ..= ARC_STEPS {
			angle := math.to_radians(arc.start + 90 * f32(step) / ARC_STEPS)
			points[n] = {arc.cx + math.cos(angle) * arc.rx, arc.cy + math.sin(angle) * arc.ry}
			n += 1
		}
	}
	return
}

// The border side a segment of the outline belongs to: the first half of a
// corner's arc to the side before it, the second half (and the straight
// piece after it) to the side after it.
@(private)
side_of_segment :: proc(i: int) -> dom.Edge {
	corner := i / (ARC_STEPS + 1)
	first_half := i % (ARC_STEPS + 1) < ARC_STEPS / 2
	// clockwise: top-left arc lies between left and top, and so on
	before := [4]dom.Edge{.Left, .Top, .Right, .Bottom}
	after := [4]dom.Edge{.Top, .Right, .Bottom, .Left}
	return before[corner] if first_half else after[corner]
}
