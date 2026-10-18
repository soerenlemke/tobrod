package ui

import "../dom"
import "../layout"
import rl "vendor:raylib"

// box-shadow. A blurred edge is a ramp from the full color to nothing over
// twice the blur radius, centered on the shadow's edge. We draw it as layers:
// copies of the shape from the biggest (grown by blur) to the smallest
// (shrunk by blur), each one inside the ones before. Each is transparent
// enough that a point covered by m of n layers gets m/n of the color's
// alpha (layer_color): a linear ramp instead of a Gaussian one, close
// enough at these sizes.

// Outer shadows, under the box: the last one at the bottom. They are never
// seen inside the box itself: an opaque background covers them anyway; for
// a square box without one only what lies outside it is drawn (Wikipedia's
// "box-shadow: 0 1px" line under its toolbar). A rounded box without a
// background still shows its shadow through.
@(private)
draw_outer_shadows :: proc(x, y: f32, box: layout.Box) {
	cut_out := box.color[3] < 255 && box.radius == {}
	shadows := box.shadows
	for i := shadows.count - 1; i >= 0; i -= 1 {
		s := shadows.list[i]
		if s.inset || s.color[3] == 0 {
			continue
		}
		layers := shadow_layers(s)
		for layer in 0 ..< layers {
			color := layer_color(s.color, layer, layers)
			grow := s.spread + layer_offset(s.blur, layer, layers)
			radius: [dom.Corner]f32
			for corner in dom.Corner {
				// corners grow with the shadow (a blurred square corner gets round too)
				radius[corner] = max(box.radius[corner] + grow, 0) if box.radius[corner] > 0 || grow > 0 else 0
			}
			sx, sy, sw, sh := x + s.x - grow, y + s.y - grow, box.width + 2 * grow, box.height + 2 * grow
			if cut_out {
				fill_outside(sx, sy, sw, sh, {x, y, box.width, box.height}, color)
			} else {
				fill_shape(sx, sy, sw, sh, radius, color)
			}
		}
	}
}

// Inset shadows, inside the padding box over the background: the padding
// box minus a hole (the padding box offset by x/y and shrunk by spread).
// Rounded corners are drawn square.
@(private)
draw_inset_shadows :: proc(x, y: f32, box: layout.Box) {
	shadows := box.shadows
	px, py := x + box.border[.Left], y + box.border[.Top]
	pw := box.width - box.border[.Left] - box.border[.Right]
	ph := box.height - box.border[.Top] - box.border[.Bottom]
	if pw <= 0 || ph <= 0 {
		return
	}
	for i := shadows.count - 1; i >= 0; i -= 1 {
		s := shadows.list[i]
		if !s.inset || s.color[3] == 0 {
			continue
		}
		layers := shadow_layers(s)
		for layer in 0 ..< layers {
			// the biggest frame (the most shrunk hole) first
			color := layer_color(s.color, layer, layers)
			shrink := s.spread + layer_offset(s.blur, layer, layers)
			// the hole, cut to the padding box
			hx0 := clamp(px + s.x + shrink, px, px + pw)
			hy0 := clamp(py + s.y + shrink, py, py + ph)
			hx1 := clamp(px + s.x + pw - shrink, px, px + pw)
			hy1 := clamp(py + s.y + ph - shrink, py, py + ph)
			if hx1 <= hx0 || hy1 <= hy0 {
				rl.DrawRectangleRec({px, py, pw, ph}, color) // no hole left
				continue
			}
			rl.DrawRectangleRec({px, py, pw, hy0 - py}, color)               // above the hole
			rl.DrawRectangleRec({px, hy1, pw, py + ph - hy1}, color)         // below
			rl.DrawRectangleRec({px, hy0, hx0 - px, hy1 - hy0}, color)       // left
			rl.DrawRectangleRec({hx1, hy0, px + pw - hx1, hy1 - hy0}, color) // right
		}
	}
}

// How many layers a shadow is drawn with.
@(private)
shadow_layers :: proc(s: layout.Box_Shadow) -> int {
	if s.blur <= 0 {
		return 1
	}
	return clamp(int(s.blur / 1.5) + 2, 2, 16)
}

// The color of layer m (0-based) of n, drawn over the m layers before it:
// with alpha blending, A_m+1 = A_m + alpha (1 - A_m), and A should go up by
// a/n with every layer.
@(private)
layer_color :: proc(c: dom.Color, m, n: int) -> rl.Color {
	a := f32(c[3]) / 255
	before := a * f32(m) / f32(n)
	after := a * f32(m + 1) / f32(n)
	alpha := (after - before) / max(1 - before, 1e-6)
	return {c.r, c.g, c.b, u8(clamp(alpha * 255 + 0.5, 1, 255))}
}

// How far layer i of n is grown: from +blur (the faint outside) to -blur.
@(private)
layer_offset :: proc(blur: f32, i, n: int) -> f32 {
	if n <= 1 {
		return 0
	}
	return blur * (1 - 2 * (f32(i) + 0.5) / f32(n))
}

// A filled rectangle, with rounded corners if it has any.
@(private)
fill_shape :: proc(x, y, w, h: f32, radius: [dom.Corner]f32, color: rl.Color) {
	if w <= 0 || h <= 0 {
		return
	}
	if radius == {} {
		rl.DrawRectangleRec({x, y, w, h}, color)
		return
	}
	limited := radius
	for &r in limited {
		r = min(r, w / 2, h / 2)
	}
	points := outline(x, y, w, h, limited, {})
	middle := rl.Vector2{x + w / 2, y + h / 2}
	for i in 0 ..< OUTLINE_POINTS {
		draw_triangle_any_order(middle, points[i], points[(i + 1) % OUTLINE_POINTS], color)
	}
}

// A rectangle minus the part of it inside box: up to four bands.
@(private)
fill_outside :: proc(x, y, w, h: f32, box: rl.Rectangle, color: rl.Color) {
	x1, y1 := x + w, y + h
	bx0, by0, bx1, by1 := box.x, box.y, box.x + box.width, box.y + box.height
	band :: proc(x0, y0, x1, y1: f32, color: rl.Color) {
		if x1 > x0 && y1 > y0 {
			rl.DrawRectangleRec({x0, y0, x1 - x0, y1 - y0}, color)
		}
	}
	band(x, y, x1, min(y1, by0), color) // above the box
	band(x, max(y, by1), x1, y1, color) // below
	mid0, mid1 := max(y, by0), min(y1, by1)
	band(x, mid0, min(x1, bx0), mid1, color) // left
	band(max(x, bx1), mid0, x1, mid1, color) // right
}
