package svg

import "core:testing"
import "../dom"

@(test)
test_numbers :: proc(t: ^testing.T) {
	// numbers can run together: "1.5.5-2" is 1.5, .5 and -2
	n := numbers_of("1,2 3-4.5e1 1.5.5-2")
	testing.expect_value(t, len(n), 7)
	if len(n) != 7 do return
	testing.expect_value(t, n[3], -45)
	testing.expect_value(t, n[5], 0.5)
	testing.expect_value(t, n[6], -2)
}

@(test)
test_transform :: proc(t: ^testing.T) {
	// translate(10 20) scale(2): first scaled, then moved
	m, ok := parse_transform("translate(10 20) scale(2)")
	testing.expect(t, ok, "valid")
	testing.expect_value(t, apply(m, {1, 1}), Point{12, 22})
	r, _ := parse_transform("rotate(90)")
	p := apply(r, {1, 0})
	testing.expect(t, abs(p.x) < 0.001 && abs(p.y - 1) < 0.001, "rotated by 90 degrees")
	_, bad := parse_transform("wobble(3)")
	testing.expect(t, !bad, "unknown function")
}

@(test)
test_path_commands :: proc(t: ^testing.T) {
	pb := path_builder(IDENTITY)
	// relative and absolute lines, H/V, implicit lineto after M, Z; arc flags
	// written together ("a1 1 0 01 2 0")
	parse_path(&pb, "M10 10 20 10 v10 H10z m5 5 l1 0 a1 1 0 01 2 0")
	testing.expect(t, len(pb.polygons) >= 2, "two subpaths")
	first := pb.polygons[0]
	testing.expect_value(t, len(first), 4)
	if len(first) == 4 {
		testing.expect_value(t, first[1], Point{20, 10})
		testing.expect_value(t, first[2], Point{20, 20})
		testing.expect_value(t, first[3], Point{10, 20})
	}
	// m after z is relative to the start of the closed subpath (10, 10)
	last := pb.polygons[len(pb.polygons) - 1]
	testing.expect_value(t, last[0], Point{15, 15})
	end := last[len(last) - 1]
	testing.expect(t, abs(end.x - 18) < 0.01 && abs(end.y - 15) < 0.01, "the arc ends at 18,15")
}

@(private = "file")
render_svg :: proc(t: ^testing.T, source: string, width, height: int) -> (image: Image) {
	doc, err := dom.parse(source)
	if e, ok := err.?; ok {
		testing.fail_now(t, e.message)
	}
	defer dom.destroy(doc)
	root := find_root(doc.root)
	if root == nil {
		testing.fail_now(t, "no svg")
	}
	return render(root, width, height, context.temp_allocator)
}

@(private = "file")
pixel :: proc(image: Image, x, y: int) -> [4]u8 {
	return image.pixels[y * image.width + x]
}

@(test)
test_render_shapes :: proc(t: ^testing.T) {
	image := render_svg(t, `<svg viewBox="0 0 10 10">
		<rect x="0" y="0" width="5" height="5" fill="red"/>
		<circle cx="7.5" cy="7.5" r="2" fill="#00f"/>
		<path d="M5 0 H10 V5 Z" fill="lime" fill-opacity="0.5"/>
	</svg>`, 20, 20)

	// the viewBox is scaled by 2
	testing.expect_value(t, pixel(image, 2, 2), [4]u8{255, 0, 0, 255})
	testing.expect_value(t, pixel(image, 15, 15), [4]u8{0, 0, 255, 255})
	testing.expect_value(t, pixel(image, 2, 15), [4]u8{0, 0, 0, 0}) // nothing there
	// half transparent green in the upper right triangle
	testing.expect_value(t, pixel(image, 18, 2), [4]u8{0, 255, 0, 128})
	// an edge pixel of the circle is partly covered: smooth edges
	edge := pixel(image, 11, 15)
	testing.expect(t, edge[3] > 0 && edge[3] < 255, "anti-aliased edge")
}

@(test)
test_render_rules_and_groups :: proc(t: ^testing.T) {
	// evenodd: the inner square is a hole; the group's fill and transform
	// are inherited
	image := render_svg(t, `<svg width="20" height="10">
		<g fill="#0f0" transform="translate(10 0)">
			<path fill-rule="evenodd" d="M0 0h10v10H0z M3 3h4v4H3z"/>
		</g>
		<path d="M0 0h10v10H0z M3 3h4v4H3z"/>
	</svg>`, 20, 10)

	testing.expect_value(t, pixel(image, 11, 1), [4]u8{0, 255, 0, 255})
	testing.expect_value(t, pixel(image, 15, 5), [4]u8{0, 0, 0, 0}) // the hole
	// nonzero (the default): both squares go the same way, no hole; black
	testing.expect_value(t, pixel(image, 5, 5), [4]u8{0, 0, 0, 255})
}

@(test)
test_render_paint :: proc(t: ^testing.T) {
	// fill="none", currentColor from color, a gradient by its first stop,
	// style="" wins over the attribute, display:none
	image := render_svg(t, `<svg width="40" height="10" color="#00f">
		<defs><linearGradient id="g"><stop offset="0" stop-color="#f00"/><stop offset="1" stop-color="#00f"/></linearGradient></defs>
		<rect width="10" height="10" fill="none"/>
		<rect x="10" width="10" height="10" fill="currentColor"/>
		<rect x="20" width="10" height="10" fill="url(#g)"/>
		<rect x="30" width="10" height="10" fill="red" style="fill: #0f0"/>
		<rect width="40" height="10" fill="black" style="display: none"/>
	</svg>`, 40, 10)

	testing.expect_value(t, pixel(image, 5, 5), [4]u8{0, 0, 0, 0})
	testing.expect_value(t, pixel(image, 15, 5), [4]u8{0, 0, 255, 255})
	testing.expect_value(t, pixel(image, 25, 5), [4]u8{255, 0, 0, 255})
	testing.expect_value(t, pixel(image, 35, 5), [4]u8{0, 255, 0, 255})
}

@(test)
test_natural_size :: proc(t: ^testing.T) {
	cases := []struct {
		source:   string,
		size:     [2]f32,
		has_size: bool,
	} {
		{`<svg width="40" height="20"></svg>`, {40, 20}, true},
		// only a viewBox: no size of its own, only the aspect ratio
		{`<svg viewBox="0 0 24 12"></svg>`, {24, 12}, false},
		{`<svg width="48" viewBox="0 0 24 12"></svg>`, {48, 24}, true},
		{`<svg></svg>`, DEFAULT_SIZE, true},
	}
	for c in cases {
		doc, _ := dom.parse(c.source)
		size, has_size := natural_size(find_root(doc.root))
		testing.expectf(t, size == c.size && has_size == c.has_size, "%s: %v %v", c.source, size, has_size)
		dom.destroy(doc)
	}
}

@(test)
test_decode :: proc(t: ^testing.T) {
	// a file of its own, with an XML declaration, at twice its size
	data := `<?xml version="1.0"?><svg xmlns="http://www.w3.org/2000/svg" width="4" height="2"><rect width="4" height="2" fill="#123456"/></svg>`
	image, natural, has_size, ok := decode(transmute([]u8)data, 2, context.temp_allocator)
	testing.expect(t, ok && has_size, "decoded")
	testing.expect_value(t, natural, [2]f32{4, 2})
	testing.expect_value(t, image.width, 8)
	testing.expect_value(t, image.height, 4)
	if ok {
		testing.expect_value(t, image.pixels[0], [4]u8{0x12, 0x34, 0x56, 255})
	}
	_, _, _, bad := decode(transmute([]u8)string("not an svg"), 1, context.temp_allocator)
	testing.expect(t, !bad, "no svg element")
}

@(test)
test_render_strokes :: proc(t: ^testing.T) {
	// a 4px wide horizontal line from x 10 to 30 at y 10, three caps
	image := render_svg(t, `<svg width="40" height="60">
		<line x1="10" y1="10" x2="30" y2="10" stroke="#f00" stroke-width="4"/>
		<line x1="10" y1="30" x2="30" y2="30" stroke="#f00" stroke-width="4" stroke-linecap="round"/>
		<line x1="10" y1="50" x2="30" y2="50" stroke="#f00" stroke-width="4" stroke-linecap="square"/>
	</svg>`, 40, 60)

	testing.expect_value(t, pixel(image, 20, 9), [4]u8{255, 0, 0, 255}) // inside the width
	testing.expect_value(t, pixel(image, 20, 13), [4]u8{0, 0, 0, 0})    // outside
	testing.expect_value(t, pixel(image, 8, 9)[3], 0)                   // butt: nothing past the end
	testing.expect(t, pixel(image, 8, 30)[3] > 0, "round cap past the end")
	testing.expect_value(t, pixel(image, 8, 49), [4]u8{255, 0, 0, 255}) // square cap: half the width further
}

@(test)
test_render_joins :: proc(t: ^testing.T) {
	// a right angle, 6px wide: the outer corner is at (26, 4) with miter,
	// cut off with bevel; and a rectangle's closed corner
	image := render_svg(t, `<svg width="80" height="40">
		<polyline points="5,7 23,7 23,30" fill="none" stroke="#00f" stroke-width="6"/>
		<polyline points="45,7 63,7 63,30" fill="none" stroke="#00f" stroke-width="6" stroke-linejoin="bevel"/>
	</svg>`, 80, 40)

	testing.expect_value(t, pixel(image, 25, 4), [4]u8{0, 0, 255, 255}) // miter: the corner is filled
	testing.expect_value(t, pixel(image, 65, 4)[3], 0)                  // bevel: cut off

	closed := render_svg(t, `<svg width="20" height="20"><rect x="4" y="4" width="12" height="12" fill="none" stroke="#000" stroke-width="2"/></svg>`, 20, 20)
	testing.expect_value(t, pixel(closed, 3, 3), [4]u8{0, 0, 0, 255}) // the first corner is joined too
	testing.expect_value(t, pixel(closed, 10, 10)[3], 0)              // no fill
}

@(test)
test_render_stroke_and_fill :: proc(t: ^testing.T) {
	// the stroke is drawn over the fill, scaled with the transform; stroke
	// is inherited from the group
	image := render_svg(t, `<svg viewBox="0 0 10 10"><g stroke="#f00" stroke-width="1">
		<rect x="2" y="2" width="6" height="6" fill="#0f0"/>
	</g></svg>`, 40, 40)

	testing.expect_value(t, pixel(image, 20, 20), [4]u8{0, 255, 0, 255}) // fill inside
	testing.expect_value(t, pixel(image, 20, 7), [4]u8{255, 0, 0, 255})  // the edge at y = 2 * 4 = 8, 4px wide
	testing.expect_value(t, pixel(image, 20, 10), [4]u8{0, 255, 0, 255}) // inside again
}
