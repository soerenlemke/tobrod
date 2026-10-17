package layout

import "../dom"

// width, min-width and max-width of a box, as the width of its content box,
// which is what the layout works with. With box-sizing: border-box they
// include padding and border (inset = their sum on that axis), so that is
// taken off. min-width wins over max-width, like in CSS.

// The content width from width; false if it is auto.
@(private)
specified_width :: proc(b: ^Builder, style: dom.Style, available, inset: f32) -> (f32, bool) {
	if style.width.unit == .Auto {
		return 0, false
	}
	return content_size(b, style, style.width, available, inset), true
}

// min-width and max-width applied to a content width.
@(private)
clamp_width :: proc(b: ^Builder, style: dom.Style, available, inset, width: f32) -> f32 {
	width := width
	if style.max_width.unit != .Auto {
		width = min(width, content_size(b, style, style.max_width, available, inset))
	}
	if style.min_width.unit != .Auto && style.min_width.value > 0 {
		width = max(width, content_size(b, style, style.min_width, available, inset))
	}
	return max(width, 0)
}

// The margin box width of a shrink-to-fit box (float, inline block, absolute
// element), with min-width and max-width applied to its content width.
// extra = inset + margins on both sides.
@(private)
clamp_outer_width :: proc(b: ^Builder, style: dom.Style, available, inset, extra, outer: f32) -> f32 {
	return clamp_width(b, style, available, inset, outer - extra) + extra
}

// A length of the box (width, height, min-/max-...) as a content size.
@(private)
content_size :: proc(b: ^Builder, style: dom.Style, length: dom.Length, available, inset: f32) -> f32 {
	size := dom.resolve_length(length, style.font_size, available, b.viewport)
	if style.border_box {
		size -= inset
	}
	return max(size, 0)
}
