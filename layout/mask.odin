package layout

import "../dom"

// mask-image: the ui draws the box's background only where the mask image is
// opaque. That is how pages draw most of their icons: an element with a
// background color (often currentColor) and an SVG as the mask. Here the
// layout works out where the image goes in the box, like for a background
// image: its size (mask-size), its position (mask-position) and whether it
// repeats. The mask covers the border box; the box's borders and the
// element's content are not masked (icons have neither).
Box_Mask :: struct {
	src:    string,  // as written in the CSS, also the key for Image_Sizes ("" = none)
	tile:   [4]f32,  // x, y (relative to the box, so it moves along), width, height of the image
	repeat: [2]bool, // x, y: tiles of the same size fill the box from there
}

// Until the mask image is loaded its size is unknown; the ui doesn't draw the
// box then (a mask that isn't there yet hides the element, like in Firefox).
@(private)
set_box_mask :: proc(b: ^Builder, box: ^Box, style: dom.Style) {
	m := style.mask
	if m.image == "" {
		return
	}
	area := [2]f32{box.width, box.height}
	natural, loaded := b.image_sizes[m.image]
	n := natural.size
	if !loaded || n.x <= 0 || n.y <= 0 {
		n = area // no size of its own: as big as the box
	}

	size: [2]f32
	switch m.size {
	case .Contain, .Cover:
		scale := min(area.x / n.x, area.y / n.y)
		if m.size == .Cover {
			scale = max(area.x / n.x, area.y / n.y)
		}
		size = n * scale
	case .Explicit:
		resolve :: proc(b: ^Builder, l: dom.Length, style: dom.Style, of: f32) -> (f32, bool) {
			if l.unit == .Auto {
				return 0, false
			}
			return dom.resolve_length(l, style.font_size, of, b.viewport), true
		}
		w, has_w := resolve(b, m.width, style, area.x)
		h, has_h := resolve(b, m.height, style, area.y)
		switch {
		case has_w && has_h:
			size = {w, h}
		case has_w:
			size = {w, w * n.y / n.x} // the other side keeps the aspect ratio
		case:
			size = {h * n.x / n.y, h}
		}
	case .Auto:
		size = n
		if loaded && natural.ratio_only {
			// only an aspect ratio: as big as fits (contain)
			size = n * min(area.x / n.x, area.y / n.y)
		}
	}

	// a percentage refers to the free space: 100% puts the right edges together
	x := dom.resolve_length(m.position.x, style.font_size, area.x - size.x, b.viewport)
	y := dom.resolve_length(m.position.y, style.font_size, area.y - size.y, b.viewport)
	box.mask = {
		src    = m.image,
		tile   = {x, y, size.x, size.y},
		repeat = {!m.no_repeat.x, !m.no_repeat.y},
	}
}
