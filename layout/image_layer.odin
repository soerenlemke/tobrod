package layout

import "../dom"

// Images in a box: background-image, and mask-image (the ui draws the box's
// background only where the mask image is opaque; that is how pages draw
// most of their icons: an element with a background color, often
// currentColor, and an SVG as the mask). Here the layout works out where the
// image goes in the box: its size (-size), its position (-position) and
// whether it repeats. A background is positioned in the padding box, a mask
// in the border box; both repeat over the whole border box. The box's
// borders and the element's content are not masked (icons have neither).
Box_Image :: struct {
	src:    string,  // as written in the CSS, also the key for Image_Sizes ("" = none)
	tile:   [4]f32,  // x, y (relative to the box, so it moves along), width, height of the image
	repeat: [2]bool, // x, y: tiles of the same size fill the box from there
	fade:   f32,     // opacity, as in Image_Item (background images)
}

// Until an image is loaded its size is unknown; the ui doesn't draw it then
// (and a mask that isn't there yet hides the box, like in Firefox).
@(private)
set_box_images :: proc(b: ^Builder, box: ^Box, style: dom.Style) {
	box.mask = place_image(b, style.mask, style, {0, 0}, {box.width, box.height})
	inset := [2]f32{box.border[.Left], box.border[.Top]}
	padding_box := [2]f32{box.width - box.border[.Left] - box.border[.Right], box.height - box.border[.Top] - box.border[.Bottom]}
	box.background_image = place_image(b, style.background_image, style, inset, padding_box)
	box.background_image.fade = item_fade(b, style)
}

// One image in its positioning area (origin and size relative to the box).
@(private)
place_image :: proc(b: ^Builder, layer: dom.Image_Layer, style: dom.Style, origin, area: [2]f32) -> Box_Image {
	if layer.image == "" {
		return {}
	}
	natural, loaded := b.image_sizes[layer.image]
	n := natural.size
	if !loaded || n.x <= 0 || n.y <= 0 {
		n = area // no size of its own: as big as the area
	}
	if n.x <= 0 || n.y <= 0 {
		return {}
	}

	size: [2]f32
	switch layer.size {
	case .Contain, .Cover:
		scale := min(area.x / n.x, area.y / n.y)
		if layer.size == .Cover {
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
		w, has_w := resolve(b, layer.width, style, area.x)
		h, has_h := resolve(b, layer.height, style, area.y)
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
	x := dom.resolve_length(layer.position.x, style.font_size, area.x - size.x, b.viewport)
	y := dom.resolve_length(layer.position.y, style.font_size, area.y - size.y, b.viewport)
	return {
		src    = layer.image,
		tile   = {origin.x + x, origin.y + y, size.x, size.y},
		repeat = {!layer.no_repeat.x, !layer.no_repeat.y},
	}
}

// box-shadow in px, the color faded by opacity. Outer shadows are drawn
// under the box (the border box offset by x/y and grown by spread), inset
// ones inside its padding box over the background; blur softens the edge.
Box_Shadow :: struct {
	x, y, blur, spread: f32,
	color:              dom.Color,
	inset:              bool,
}

Box_Shadows :: struct {
	list:  [dom.MAX_SHADOWS]Box_Shadow,
	count: int,
}

@(private)
set_box_shadows :: proc(b: ^Builder, box: ^Box, style: dom.Style) {
	fade := item_fade(b, style)
	shadows := style.box_shadow
	for s, i in shadows.list[:shadows.count] {
		resolve :: proc(b: ^Builder, l: dom.Length, style: dom.Style) -> f32 {
			return dom.resolve_length(l, style.font_size, 0, b.viewport)
		}
		box.shadows.list[i] = {
			x      = resolve(b, s.x, style),
			y      = resolve(b, s.y, style),
			blur   = max(resolve(b, s.blur, style), 0),
			spread = resolve(b, s.spread, style),
			color  = dom.faded(s.color.? or_else style.color, fade),
			inset  = s.inset,
		}
	}
	box.shadows.count = style.box_shadow.count
}
