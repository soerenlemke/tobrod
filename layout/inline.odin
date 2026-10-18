package layout

import "../dom"

// Inline elements with a background, border, padding or margin (span, code,
// mark, a "badge"). Horizontally, the left side (margin, border, padding)
// makes room before the first piece of content, the right side after the
// last. A background or border is drawn as one box per line the element is
// on: its runs and images are next to each other in the line, so a fragment
// only remembers where they start and end. The left border belongs to the
// first fragment, the right one to the last (box-decoration-break: slice).
// Vertically the box covers the content area of the element's font (not its
// line-height) plus padding and border, which don't make the line higher -
// like in CSS.

@(private)
Inline_Fragment :: struct {
	node:                     ^dom.Node,
	first_run, end_run:       int, // in b.line; end -1 while the element is open
	first_image, end_image:   int, // in b.line_images
	starts:                   bool, // the element starts on this line
	shown:                    bool, // something of it is on the current line
	padding, border:          [dom.Edge]f32,
	offset:                   [2]f32, // position: relative of the element (and around it)
}

// Whether an inline element needs a fragment: it draws something or takes
// room at its sides.
@(private)
inline_decorated :: proc(style: dom.Style) -> bool {
	if style.background[3] > 0 {
		return true
	}
	for edge in dom.Edge {
		if style.border[edge].style != .None || !dom.is_zero(style.padding[edge]) {
			return true
		}
	}
	return (style.margin[.Left].unit != .Auto && !dom.is_zero(style.margin[.Left])) ||
		(style.margin[.Right].unit != .Auto && !dom.is_zero(style.margin[.Right]))
}

@(private)
begin_inline :: proc(b: ^Builder, node: ^dom.Node) {
	style := node.style
	available := b.right - b.left
	margin, padding, border, _ := box_edges(b, style, available)
	append(&b.inline_fragments, Inline_Fragment {
		node        = node,
		first_run   = len(b.line),
		end_run     = -1,
		first_image = len(b.line_images),
		end_image   = -1,
		starts      = true,
		padding     = padding,
		border      = border,
		offset      = b.offset,
	})
	// the left side goes before the next word or image (which may still
	// move to the next line)
	b.pending_inline_left += margin[.Left] + border[.Left] + padding[.Left]
	b.can_extend = false
}

@(private)
end_inline :: proc(b: ^Builder, node: ^dom.Node) {
	#reverse for &f in b.inline_fragments {
		if f.node == node && f.end_run < 0 {
			f.end_run, f.end_image = len(b.line), len(b.line_images)
			margin, _, _, _ := box_edges(b, node.style, b.right - b.left)
			right := f.padding[.Right] + f.border[.Right] + margin[.Right]
			if line_empty(b) {
				b.pending_inline_left += right // nothing of it on this line (yet)
			} else {
				b.x += right
			}
			break
		}
	}
	b.can_extend = false
}

// The room an inline element wants before the next word or image.
@(private)
take_inline_left :: proc(b: ^Builder) -> (extra: f32) {
	extra = b.pending_inline_left
	b.pending_inline_left = 0
	return
}

// Called by finish_line once the runs and images of the line have their final
// position: one box per fragment with a background or border. Fragments of
// elements that go on continue on the next line.
@(private)
place_inline_boxes :: proc(b: ^Builder, line_top, line_height: f32) {
	if len(b.inline_fragments) == 0 {
		return
	}
	for &f in b.inline_fragments {
		ends := f.end_run >= 0
		end_run := f.end_run if ends else len(b.line)
		end_image := f.end_image if ends else len(b.line_images)

		left, right := max(f32), min(f32)
		for run, i in b.line[f.first_run:end_run] {
			if f.first_run + i + 1 == b.marker_run {
				continue // the list marker hangs outside
			}
			left, right = min(left, run.x), max(right, run.x + run.width)
		}
		for image in b.line_images[f.first_image:end_image] {
			left, right = min(left, image.x), max(right, image.x + image.width)
		}
		f.shown = left <= right
		if !f.shown {
			continue // nothing of it on this line
		}

		style := f.node.style
		border := f.border
		if f.starts {
			left -= f.padding[.Left] + f.border[.Left]
		} else {
			border[.Left] = 0
		}
		if ends {
			right += f.padding[.Right] + f.border[.Right]
		} else {
			border[.Right] = 0
		}
		b.extent = max(b.extent, right)
		has_border := border[.Top] > 0 || border[.Right] > 0 || border[.Bottom] > 0 || border[.Left] > 0
		if (style.background[3] == 0 && !has_border) || style.visibility != .Visible {
			continue
		}

		// the content area of the element's font around its text, which sits
		// in the middle of the element's line box at the bottom of the line
		own := dom.line_height_px(style)
		text_top := line_top + line_height - own + (own - style.font_size) / 2
		content := style.font_size * CONTENT_AREA_FACTOR
		top := text_top - (content - style.font_size) / 2 - f.padding[.Top] - border[.Top]
		box := Box {
			x      = left,
			y      = top + f.offset.y,
			width  = right - left,
			height = content + f.padding[.Top] + f.padding[.Bottom] + border[.Top] + border[.Bottom],
			color  = style.background,
			border = border,
		}
		// rounded corners only where the element starts and ends
		box.radius = box_radius(b, style, box.width, box.height)
		if !f.starts {
			box.radius[.Top_Left], box.radius[.Bottom_Left] = 0, 0
		}
		if !ends {
			box.radius[.Top_Right], box.radius[.Bottom_Right] = 0, 0
		}
		for edge in dom.Edge {
			box.border_color[edge] = dom.border_color(style.border[edge], style.color)
		}
		append(&b.layout.boxes, box)
	}

	// elements that are done are forgotten, open ones continue on the next line
	open := 0
	for f in b.inline_fragments {
		if f.end_run < 0 {
			next := f
			next.first_run, next.first_image = 0, 0
			next.starts = f.starts && !f.shown // the left side is still to come
			b.inline_fragments[open] = next
			open += 1
		}
	}
	resize(&b.inline_fragments, open)
}
