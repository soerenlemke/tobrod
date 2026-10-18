package svg

import "core:slice"

// A scanline rasterizer: fills polygons into an RGBA picture, with smooth
// (anti-aliased) edges.
//
// For every pixel row we look at SUBSAMPLES lines across it. On each line,
// every edge of the polygons crosses at some x; sorted by x, the crossings
// tell where the line is inside the shape (fill-rule: nonzero counts the
// direction of the edges, evenodd only how many there were). The inside
// spans are added to a coverage row with their exact horizontal extent, so
// a pixel half covered by a span gets half of it. Then the color is blended
// in with that coverage.

SUBSAMPLES :: 4

Fill_Rule :: enum {
	Nonzero,
	Evenodd,
}

Edge :: struct {
	x0, y0, x1, y1: f32, // y0 < y1
	dir:            int, // +1 downwards, -1 upwards (for nonzero)
}

// Fills the polygons (closed implicitly) with color (straight alpha, 0..1
// opacity on top) into pixels (width x height, RGBA, straight alpha).
fill :: proc(pixels: [][4]u8, width, height: int, polygons: []Polygon, rule: Fill_Rule, color: [4]u8, opacity: f32) {
	edges := make([dynamic]Edge, context.temp_allocator)
	min_y, max_y := f32(height), f32(0)
	for poly in polygons {
		n := len(poly)
		if n < 2 {
			continue
		}
		for i in 0 ..< n {
			a, b := poly[i], poly[(i + 1) % n]
			if a.y == b.y {
				continue // horizontal edges don't cross a scanline
			}
			if a.y < b.y {
				append(&edges, Edge{a.x, a.y, b.x, b.y, 1})
			} else {
				append(&edges, Edge{b.x, b.y, a.x, a.y, -1})
			}
			min_y = min(min_y, a.y, b.y)
			max_y = max(max_y, a.y, b.y)
		}
	}
	if len(edges) == 0 {
		return
	}

	coverage := make([]f32, width + 2, context.temp_allocator)
	Crossing :: struct {
		x:   f32,
		dir: int,
	}
	crossings := make([dynamic]Crossing, context.temp_allocator)
	first_row := max(int(min_y), 0)
	last_row := min(int(max_y) + 1, height)
	for row in first_row ..< last_row {
		slice.fill(coverage, 0)
		row_min, row_max := width, -1
		for s in 0 ..< SUBSAMPLES {
			y := f32(row) + (f32(s) + 0.5) / SUBSAMPLES
			clear(&crossings)
			for e in edges {
				if y >= e.y0 && y < e.y1 {
					t := (y - e.y0) / (e.y1 - e.y0)
					append(&crossings, Crossing{e.x0 + t * (e.x1 - e.x0), e.dir})
				}
			}
			slice.sort_by(crossings[:], proc(a, b: Crossing) -> bool {return a.x < b.x})
			winding := 0
			for c, i in crossings {
				winding += c.dir
				inside := winding != 0 if rule == .Nonzero else (i + 1) % 2 == 1
				if inside && i + 1 < len(crossings) {
					add_span(coverage, c.x, crossings[i + 1].x, width, &row_min, &row_max)
				}
			}
		}
		for x in max(row_min, 0) ..= min(row_max, width - 1) {
			cov := min(coverage[x] / SUBSAMPLES, 1)
			if cov > 0 {
				blend(&pixels[row * width + x], color, cov * opacity)
			}
		}
	}
}

// Adds the span [x0, x1) to the coverage row: whole pixels get 1, the pixels
// at the ends the part that is covered.
@(private)
add_span :: proc(coverage: []f32, x0, x1: f32, width: int, row_min, row_max: ^int) {
	x0, x1 := max(x0, 0), min(x1, f32(width))
	if x1 <= x0 {
		return
	}
	first, last := int(x0), int(x1)
	if first == last {
		coverage[first] += x1 - x0
	} else {
		coverage[first] += f32(first + 1) - x0
		for x in first + 1 ..< last {
			coverage[x] += 1
		}
		if last < width {
			coverage[last] += x1 - f32(last)
		}
	}
	row_min^ = min(row_min^, first)
	row_max^ = max(row_max^, min(last, width - 1))
}

// "source over destination" with straight (not premultiplied) alpha.
@(private)
blend :: proc(dst: ^[4]u8, color: [4]u8, coverage: f32) {
	sa := f32(color[3]) / 255 * coverage
	if sa <= 0 {
		return
	}
	da := f32(dst[3]) / 255
	out_a := sa + da * (1 - sa)
	for i in 0 ..< 3 {
		c := (f32(color[i]) * sa + f32(dst[i]) * da * (1 - sa)) / out_a
		dst[i] = u8(clamp(c + 0.5, 0, 255))
	}
	dst[3] = u8(clamp(out_a * 255 + 0.5, 0, 255))
}
