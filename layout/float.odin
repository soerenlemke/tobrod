package layout

import "../dom"

// Floats (float: left/right). A float is taken out of the normal flow and
// pushed to the left or right edge; the lines next to it get shorter, text
// flows around it. Block boxes (backgrounds) are not affected, only their
// lines - like in a browser.
//
// Floats belong to a block formatting context: the page, a table cell or the
// float itself. Floats inside a cell don't affect anything outside of it.

@(private)
Float_Box :: struct {
	x, y, width, height: f32, // margin box
	side:                dom.Float,
}

// Lays out a floated element: width, position, then its content at that place.
@(private)
layout_float :: proc(b: ^Builder, node: ^dom.Node) {
	style := node.style
	available := b.right - b.left
	margin, _, _, inset := box_edges(b, style, available) // auto margins resolve to 0

	// width of the margin box: an explicit width, or "shrink-to-fit": as wide
	// as the content wants (max-content), but not wider than the space, and
	// never narrower than its narrowest form (min-content)
	width: f32
	if style.width.unit != .Auto && style.display != .Table {
		width = dom.resolve_length(style.width, style.font_size, available, b.viewport) +
			inset[.Left] + inset[.Right] + margin[.Left] + margin[.Right]
	} else {
		right_extra := inset[.Right] + margin[.Right]
		max_content := measure_node(b, node, MAX_CONTENT_WIDTH) + right_extra
		min_content := measure_node(b, node, 0) + right_extra
		width = min(max(min_content, available), max_content)
	}

	// vertically where the next line would start, not above earlier floats
	y := b.y if !line_empty(b) else b.y + b.pending_margin
	y = max(y, b.last_float_top)
	if style.clear != .None {
		y = max(y, clear_y(b, style.clear))
	}
	// horizontally at its edge; if it doesn't fit next to other floats, it
	// moves down below them
	x: f32
	for {
		left, right := line_bounds(b, y, 1)
		if right - left >= width || !narrowed(b, left, right) {
			x = left if style.float == .Left else right - width
			break
		}
		y = next_float_bottom(b, y, 1) or_break
	}

	bottom := layout_in_own_context(b, node, x, x + width, y, node)
	append(&b.floats, Float_Box{x, y, width, bottom - y, style.float})
	b.last_float_top = y
}

// The space a line at y with the given height has next to the floats.
@(private)
line_bounds :: proc(b: ^Builder, y, height: f32) -> (left, right: f32) {
	left, right = b.left, b.right
	for f in b.floats {
		if f.y < y + height && f.y + f.height > y {
			if f.side == .Left {
				left = max(left, f.x + f.width)
			} else {
				right = min(right, f.x)
			}
		}
	}
	return
}

@(private)
narrowed :: proc(b: ^Builder, left, right: f32) -> bool {
	return left > b.left || right < b.right
}

// The bottom of the float that ends first among those next to [y, y+height):
// where a line that doesn't fit beside them can go instead.
@(private)
next_float_bottom :: proc(b: ^Builder, y, height: f32) -> (bottom: f32, ok: bool) {
	bottom = max(f32)
	for f in b.floats {
		if f.y < y + height && f.y + f.height > y {
			bottom = min(bottom, f.y + f.height)
			ok = true
		}
	}
	return
}

// Below all floats of the given side(s): where a block with clear goes.
@(private)
clear_y :: proc(b: ^Builder, clear: dom.Clear) -> f32 {
	y := b.y
	for f in b.floats {
		if clear == .Both || (clear == .Left && f.side == .Left) || (clear == .Right && f.side == .Right) {
			y = max(y, f.y + f.height)
		}
	}
	return y
}

// Moves the start of the current (empty) line down until a piece of the
// given width fits next to the floats, then updates the line bounds.
@(private)
fit_line :: proc(b: ^Builder, width, height: f32) {
	for {
		left, right := line_bounds(b, b.y, height)
		if right - left >= width || !narrowed(b, left, right) {
			b.line_left, b.line_right = left, right
			b.x = left
			return
		}
		b.y = next_float_bottom(b, b.y, height) or_break
	}
	b.line_left, b.line_right = b.left, b.right
	b.x = b.left
}

// Lays out node (if layout_root) or the children of node between left and
// right, starting at top, as its own block formatting context: no margin
// collapses out of it, and floats inside stay inside (but make it higher).
// Returns where the content (including inner floats) ends. Everything about
// the surrounding layout, even a half-filled line, is restored afterwards.
@(private)
layout_in_own_context :: proc(b: ^Builder, node: ^dom.Node, left, right, top: f32, layout_root: ^dom.Node = nil) -> (bottom: f32) {
	old_left, old_right, old_x, old_y := b.left, b.right, b.x, b.y
	old_line_left, old_line_right := b.line_left, b.line_right
	old_align, old_margin, old_marker := b.text_align, b.pending_margin, b.pending_marker
	old_line, old_images := b.line, b.line_images
	old_floats, old_float_top, old_unfloat := b.floats, b.last_float_top, b.unfloat
	old_space, old_extend := b.pending_space, b.can_extend
	old_fragments, old_inline_left, old_marker_run := b.inline_fragments, b.pending_inline_left, b.marker_run
	old_line_blocks := b.line_blocks
	defer {
		b.left, b.right, b.x, b.y = old_left, old_right, old_x, old_y
		b.line_left, b.line_right = old_line_left, old_line_right
		b.text_align, b.pending_margin, b.pending_marker = old_align, old_margin, old_marker
		b.line, b.line_images = old_line, old_images
		b.floats, b.last_float_top, b.unfloat = old_floats, old_float_top, old_unfloat
		b.pending_space, b.can_extend = old_space, old_extend
		b.inline_fragments, b.pending_inline_left, b.marker_run = old_fragments, old_inline_left, old_marker_run
		b.line_blocks = old_line_blocks
	}

	b.left, b.right, b.x, b.y = left, max(right, left), left, top
	b.line_left, b.line_right = b.left, b.right
	b.text_align = node.style.text_align
	b.pending_margin = 0
	b.pending_marker = nil
	b.pending_space = false
	b.line = make([dynamic]Text_Run, b.allocator)
	b.line_images = make([dynamic]Image_Item, b.allocator)
	b.floats = make([dynamic]Float_Box, b.allocator)
	b.inline_fragments = make([dynamic]Inline_Fragment, b.allocator)
	b.line_blocks = make([dynamic]Inline_Block_Item, b.allocator)
	b.pending_inline_left, b.marker_run = 0, 0
	b.last_float_top = top
	// a resolved entry: flush_margin must not resolve the blocks around us
	append(&b.block_tops, Block_Top{top, true})
	defer pop(&b.block_tops)

	if layout_root != nil {
		b.unfloat = layout_root // lay out the float's own box, not float it again
		layout_node(b, layout_root)
	} else {
		for child in node.children {
			layout_node(b, child)
		}
	}
	finish_line(b)
	flush_margin(b) // the last bottom margin stays inside
	bottom = b.y
	for f in b.floats {
		bottom = max(bottom, f.y + f.height)
	}
	return
}

// How wide node itself becomes when laid out in the given width (for the
// shrink-to-fit width of floats). Like measure_contents, but for the node.
@(private)
measure_node :: proc(b: ^Builder, node: ^dom.Node, width: f32) -> f32 {
	return measure(b, node, width, node)
}
