package layout

import "../dom"

// display: inline-block / inline-flex: a box that is laid out inside like a
// block (or flex container) and placed in the line as a whole, like a big
// word - buttons, tags, navigation items.
//
// Its width is the width property or shrink-to-fit, like a float. Its
// content is laid out right away as its own formatting context, but at
// y = 0: where the line ends up is only known in finish_line, which moves
// everything it added (Display_Range) into place.
//
// Vertically it sits on the baseline like text: its last line of text lines
// up with the text of the line; what is below that (padding, border, margin)
// hangs below the line's text and makes the line higher there. Without text
// its bottom margin edge sits on the baseline, like an image.

@(private)
Inline_Block_Item :: struct {
	drawn:        Display_Range, // what its content added, laid out at y = 0
	x, width:     f32,           // margin box
	above, below: f32,           // height above / below its baseline
}

@(private)
layout_inline_block :: proc(b: ^Builder, node: ^dom.Node) {
	style := node.style
	available := b.right - b.left
	margin, _, _, inset := box_edges(b, style, available)

	// width of the margin box: width, or shrink-to-fit like a float
	inset_x := inset[.Left] + inset[.Right]
	extra := inset_x + margin[.Left] + margin[.Right]
	outer: f32
	if w, ok := specified_width(b, style, available, inset_x); ok {
		outer = w + extra
	} else {
		right_extra := inset[.Right] + margin[.Right]
		max_content := measure_node(b, node, MAX_CONTENT_WIDTH) + right_extra
		min_content := measure_node(b, node, 0) + right_extra
		outer = min(max(min_content, available), max_content)
	}
	outer = clamp_outer_width(b, style, available, inset_x, extra, outer)

	// into the line like a word: wrap if it doesn't fit
	space_width: f32 = 0
	if b.pending_space {
		space_width = b.measure(" ", b.space_style.font_size, font_of(b.space_style))
	}
	inline_left := b.pending_inline_left
	if !line_empty(b) && wraps_before(node) && b.x + space_width + inline_left + outer > b.line_right {
		finish_line(b)
		space_width = 0
	}
	if line_empty(b) {
		line_height := dom.line_height_px(style)
		start_line(b, line_height)
		fit_line(b, inline_left + outer, line_height)
		space_width = 0
	}
	space_width += take_inline_left(b)
	x := b.x + space_width

	// the content, at y = 0 for now
	drawn := display_range_start(b)
	old_style := fix_percentages(b, &node.style, available)
	bottom := layout_in_own_context(b, node, x, x + outer, 0, node)
	node.style = old_style
	drawn = display_range_end(b, drawn)

	// the baseline: the bottom of the line box of its last text
	above := bottom
	last_line_bottom: f32 = -1
	for run in b.layout.runs[drawn.first_run:drawn.end_run] {
		last_line_bottom = max(last_line_bottom, run.y + (run.line_height + run.font_size) / 2)
	}
	clips_x, clips_y := clips_overflow(style)
	if last_line_bottom >= 0 && !clips_x && !clips_y {
		above = min(last_line_bottom, bottom)
	}

	append(&b.line_blocks, Inline_Block_Item{drawn, x, outer, above, bottom - above})
	b.x += space_width + outer
	b.pending_space = false
	b.can_extend = false
}

// The height an inline block needs above and below the line's baseline.
@(private)
line_block_extent :: proc(b: ^Builder) -> (above, below: f32) {
	for item in b.line_blocks {
		above = max(above, item.above)
		below = max(below, item.below)
	}
	return
}

// Moves the inline blocks of the line into place: dx from text-align, the
// baseline of the line at baseline_y.
@(private)
place_line_blocks :: proc(b: ^Builder, dx, baseline_y: f32) {
	for item in b.line_blocks {
		shift_items(b, item.drawn, baseline_y - item.above, dx)
		b.extent = max(b.extent, item.x + dx + item.width)
	}
	clear(&b.line_blocks)
}
