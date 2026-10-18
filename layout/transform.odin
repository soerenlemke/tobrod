package layout

import "core:math"
import "../dom"
import "../svg"

// transform (see dom/transform_style.odin) as a matrix in the element's own
// coordinates: (0, 0) is the top left corner of its border box, so
// percentages and transform-origin can be resolved against its size.
//
// A transform that only moves (translate) is done right away: the element's
// items are shifted like with position: relative, so links and clipping
// stay right. Anything else (rotate, scale, skew) is drawn by the ui with
// the matrix: a transformed element is a stacking context with a layer of
// its own (stacking.odin), and the layer carries the matrix. Inside another
// stacking context there are no more layers, so a rotation there is lost
// (a translation still works). Replaced elements (images, inline <svg>)
// carry their matrix themselves (Image_Item.transform).

// A 2D affine matrix, as in SVG's matrix(a b c d e f).
Matrix :: svg.Matrix

// The element's transform, or false if it has none.
@(private)
element_transform :: proc(b: ^Builder, style: dom.Style, width, height: f32) -> (m: svg.Matrix, ok: bool) {
	t := style.transform
	if t.count == 0 {
		return svg.IDENTITY, false
	}
	center := dom.Length{unit = .Percent, value = 50}
	origin := t.origin.? or_else [2]dom.Length{center, center}
	ox := dom.resolve_length(origin.x, style.font_size, width, b.viewport)
	oy := dom.resolve_length(origin.y, style.font_size, height, b.viewport)

	m = translation(ox, oy)
	for fn in t.list[:t.count] {
		f := svg.IDENTITY
		switch fn.kind {
		case .Translate:
			f = translation(dom.resolve_length(fn.x, style.font_size, width, b.viewport), dom.resolve_length(fn.y, style.font_size, height, b.viewport))
		case .Scale:
			f = {fn.a[0], 0, 0, fn.a[1], 0, 0}
		case .Rotate:
			cos, sin := math.cos(fn.a[0]), math.sin(fn.a[0])
			f = {cos, sin, -sin, cos, 0, 0}
		case .Skew:
			f = {1, math.tan(fn.a[1]), math.tan(fn.a[0]), 1, 0, 0}
		case .Matrix:
			f = fn.a
		}
		m = svg.multiply(m, f) // the functions apply right to left
	}
	return svg.multiply(m, translation(-ox, -oy)), true
}

@(private)
translation :: proc(x, y: f32) -> svg.Matrix {
	return {1, 0, 0, 1, x, y}
}

// Does the matrix only move?
@(private)
is_translation :: proc(m: svg.Matrix) -> bool {
	return abs(m[0] - 1) < 1e-4 && abs(m[1]) < 1e-4 && abs(m[2]) < 1e-4 && abs(m[3] - 1) < 1e-4
}

// A matrix in the coordinates of a box at anchor, made absolute.
absolute_transform :: proc(local: svg.Matrix, anchor: [2]f32) -> svg.Matrix {
	return svg.multiply(translation(anchor.x, anchor.y), svg.multiply(local, translation(-anchor.x, -anchor.y)))
}

// After an element with a transform is laid out (its items in range, its
// border box in box): a translation moves its items now; otherwise the
// matrix and where the box is go to its layer.
@(private)
apply_element_transform :: proc(b: ^Builder, style: dom.Style, range: Display_Range, box: Placed_Box) -> (transform: Maybe(svg.Matrix), anchor: [2]f32) {
	m, ok := element_transform(b, style, box.width, box.height)
	if !ok {
		return nil, {}
	}
	if is_translation(m) {
		shift_items(b, range, m[5], m[4])
		return nil, {}
	}
	return m, {box.x, box.y}
}

@(private)
image_transform :: proc(b: ^Builder, style: dom.Style, width, height: f32) -> Maybe(svg.Matrix) {
	if m, ok := element_transform(b, style, width, height); ok {
		return m
	}
	return nil
}
