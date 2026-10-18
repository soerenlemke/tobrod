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
	if style.min_width.unit != .Auto && !dom.is_zero(style.min_width) {
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

// Floats, inline blocks and absolute elements are laid out in their own
// context, between edges worked out before. Inside, layout_block resolves
// width, margins and padding again - against that space, the box itself.
// Their percentages (also in calc()) refer to the containing block, though,
// so for that layout they are replaced by their px values. Returns the style
// as it was, to put back afterwards.
@(private)
fix_percentages :: proc(b: ^Builder, style: ^dom.Style, available: f32) -> (old: dom.Style) {
	old = style^
	fix :: proc(b: ^Builder, style: ^dom.Style, length: ^dom.Length, available: f32) {
		if dom.has_percent(length^) {
			length^ = dom.px(dom.resolve_length(length^, style.font_size, available, b.viewport))
		}
	}
	fix(b, style, &style.width, available)
	fix(b, style, &style.min_width, available)
	fix(b, style, &style.max_width, available)
	for edge in dom.Edge {
		fix(b, style, &style.margin[edge], available)
		fix(b, style, &style.padding[edge], available)
	}
	return
}

// border-radius in px for a box of this size. Percentages refer to the
// width (elliptical corners, whose vertical radius would use the height, are
// drawn round). A radius bigger than half the box is cut down, so 50% on a
// wide box gives a pill instead of an ellipse.
@(private)
box_radius :: proc(b: ^Builder, style: dom.Style, width, height: f32) -> (radius: [dom.Corner]f32) {
	limit := max(min(width, height) / 2, 0)
	for corner in dom.Corner {
		r := dom.resolve_length(style.border_radius[corner], style.font_size, width, b.viewport)
		radius[corner] = clamp(r, 0, limit)
	}
	return
}
