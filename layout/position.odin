package layout

import "../dom"

// Positioning (position: relative / absolute / fixed).
//
// relative: the element is laid out normally and then moved by its offsets
// (see layout_element), nothing else moves.
//
// absolute: the element is taken out of the flow. Its containing block is the
// padding box of the nearest positioned ancestor (or the first screen of the
// page). Because that box is only known when the ancestor is done, absolute
// elements wait there (register_absolute) and are placed in
// end_containing_block:
// - left/right/top/bottom place it against the containing block; an offset
//   that is auto keeps the "static position", where it would have been in
//   the flow
// - its width: width, else stretched between left and right, else
//   shrink-to-fit like a float; with top and bottom and no height it is
//   stretched vertically, too; percentages of height work here
// - it is laid out as its own block formatting context
//
// fixed: like absolute, but the containing block is always the viewport, and
// they don't scroll. They are placed after everything else into their own
// layer (Layout.fixed, in viewport coordinates), see place_fixed.
//
// Positioned elements are drawn on top of the normal flow. An empty clip rect
// hides an absolute element (clipped_away).

@(private)
Containing_Block :: struct {
	waiting: [dynamic]Waiting_Absolute,
}

// An absolute element and where it would have been in the normal flow.
@(private)
Waiting_Absolute :: struct {
	node:       ^dom.Node,
	static_pos: [2]f32,
}

// The border box of a block, table or flex container that was laid out.
@(private)
Placed_Box :: struct {
	x, y, width, height: f32,
	border:              [dom.Edge]f32,
	index:               int, // of its own Box in the display list, -1 if it has none
}

@(private)
begin_containing_block :: proc(b: ^Builder) {
	append(&b.containing, Containing_Block{waiting = make([dynamic]Waiting_Absolute, b.allocator)})
}

// Places the absolute elements that waited for this containing block;
// b.last_box is its border box.
@(private)
end_containing_block :: proc(b: ^Builder) {
	cb := pop(&b.containing)
	if len(cb.waiting) == 0 {
		return
	}
	box := b.last_box
	padding_box := Placed_Box {
		x      = box.x + box.border[.Left],
		y      = box.y + box.border[.Top],
		width  = box.width - box.border[.Left] - box.border[.Right],
		height = box.height - box.border[.Top] - box.border[.Bottom],
	}
	for w in cb.waiting {
		layout_absolute(b, w, padding_box)
	}
	b.last_box = box // placing them must not change what the parent sees
}

// Remembers an absolute element and its static position for later.
@(private)
register_absolute :: proc(b: ^Builder, node: ^dom.Node) {
	if b.measuring || len(b.containing) == 0 {
		return // out of the flow: doesn't count for the width of the content
	}
	wait_for_containing_block(b, node, static_position(b, node))
}

// Remembers a fixed element; place_fixed lays it out at the end.
@(private)
register_fixed :: proc(b: ^Builder, node: ^dom.Node) {
	if b.measuring {
		return
	}
	append(&b.fixed_waiting, Waiting_Absolute{node, static_position(b, node)})
}

// Where an out-of-flow element would be in the normal flow.
@(private)
static_position :: proc(b: ^Builder, node: ^dom.Node) -> (pos: [2]f32) {
	if dom.is_inline_level(node.style.display) {
		pos = {b.x, b.y if !line_empty(b) else b.y + b.pending_margin}
		if b.pending_space && !line_empty(b) {
			// after the space that waits for the next word
			pos.x += b.measure(" ", b.space_style.font_size, font_of(b.space_style))
		}
	} else {
		// a block would start on a new line
		pos = {b.left, b.y + b.pending_margin}
		if !line_empty(b) {
			pos.y = b.y + current_line_height(b)
		}
	}
	return
}

// Lays out the fixed elements against the viewport into their own layer.
// The page is not scrolled then, so a static position on the page is also
// one in the viewport.
@(private)
place_fixed :: proc(b: ^Builder) {
	if len(b.fixed_waiting) == 0 {
		return
	}
	l := b.layout
	page_boxes, page_runs, page_images := l.boxes, l.runs, l.images
	page_positioned, page_overflow := b.positioned, b.overflow
	l.boxes = make([dynamic]Box, b.allocator)
	l.runs = make([dynamic]Text_Run, b.allocator)
	l.images = make([dynamic]Image_Item, b.allocator)
	b.positioned = make([dynamic][2]int, b.allocator)

	viewport := Placed_Box{width = b.viewport.x, height = b.viewport.y, index = -1}
	for w in b.fixed_waiting {
		layout_absolute(b, w, viewport)
	}
	draw_positioned_last(b)

	l.fixed = {l.boxes, l.runs, l.images}
	l.boxes, l.runs, l.images = page_boxes, page_runs, page_images
	b.positioned, b.overflow = page_positioned, page_overflow
}

@(private)
wait_for_containing_block :: proc(b: ^Builder, node: ^dom.Node, static_pos: [2]f32) {
	if b.measuring || len(b.containing) == 0 {
		return
	}
	append(&b.containing[len(b.containing) - 1].waiting, Waiting_Absolute{node, static_pos})
}

// clip: rect(...) with no area: nothing of the element is visible. This is
// how pages hide text that is only meant for screen readers ("skip to
// content", labels of icon buttons). Other clip rects are not applied.
@(private)
clipped_away :: proc(b: ^Builder, style: dom.Style) -> bool {
	clip := style.clip.? or_return
	edge := proc(b: ^Builder, style: dom.Style, length: dom.Length) -> f32 {
		return dom.resolve_length(length, style.font_size, 0, b.viewport)
	}
	if clip[.Left].unit != .Auto && clip[.Right].unit != .Auto && edge(b, style, clip[.Right]) <= edge(b, style, clip[.Left]) {
		return true
	}
	if clip[.Top].unit != .Auto && clip[.Bottom].unit != .Auto && edge(b, style, clip[.Bottom]) <= edge(b, style, clip[.Top]) {
		return true
	}
	return false
}

@(private)
current_line_height :: proc(b: ^Builder) -> (height: f32) {
	for run in b.line {
		height = max(height, run.line_height)
	}
	for image in b.line_images {
		height = max(height, image.height)
	}
	return
}

@(private)
layout_absolute :: proc(b: ^Builder, w: Waiting_Absolute, cb: Placed_Box) {
	node := w.node
	style := &node.style
	if clipped_away(b, style^) {
		return
	}
	margin, _, _, inset := box_edges(b, style^, cb.width)

	// offsets: left/right refer to the width of the containing block,
	// top/bottom to its height
	offset: [dom.Edge]f32
	set: [dom.Edge]bool
	for edge in dom.Edge {
		length := style.offset[edge]
		if length.unit == .Auto {
			continue
		}
		base := cb.width if edge == .Left || edge == .Right else cb.height
		offset[edge] = dom.resolve_length(length, style.font_size, base, b.viewport)
		set[edge] = true
	}

	// width of the margin box
	inset_x := inset[.Left] + inset[.Right]
	extra := inset_x + margin[.Left] + margin[.Right]
	width: f32
	if w, ok := specified_width(b, style^, cb.width, inset_x); ok && style.display != .Table {
		width = w + extra
	} else if set[.Left] && set[.Right] {
		width = cb.width - offset[.Left] - offset[.Right]
	} else {
		available := cb.width - offset[.Left] - offset[.Right]
		right_extra := inset[.Right] + margin[.Right]
		max_content := measure_node(b, node, MAX_CONTENT_WIDTH) + right_extra
		min_content := measure_node(b, node, 0) + right_extra
		width = min(max(min_content, available), max_content)
	}
	width = clamp_outer_width(b, style^, cb.width, inset_x, extra, width)

	x := w.static_pos.x
	if set[.Left] {
		x = cb.x + offset[.Left]
	} else if set[.Right] {
		x = cb.x + cb.width - offset[.Right] - width
	}
	y := w.static_pos.y
	if set[.Top] {
		y = cb.y + offset[.Top]
	}

	// the height of the containing block is known here, so a percentage
	// height works (in the flow it counts as auto); top and bottom with an
	// auto height: stretched between them
	old_height, old_border_box := style.height, style.border_box
	if dom.has_percent(style.height) {
		style.height = dom.px(dom.resolve_length(style.height, style.font_size, cb.height, b.viewport))
	} else if set[.Top] && set[.Bottom] && style.height.unit == .Auto {
		// a content height (the width stays as it is, the block resolves it
		// again with the same box-sizing)
		inner := cb.height - offset[.Top] - offset[.Bottom] - margin[.Top] - margin[.Bottom] - inset[.Top] - inset[.Bottom]
		style.height = dom.px(max(inner, 0))
		if style.border_box {
			style.height = dom.px(max(inner, 0) + inset[.Top] + inset[.Bottom])
		}
	}
	placed := display_range_start(b)
	old_style := fix_percentages(b, style, cb.width)
	bottom := layout_in_own_context(b, node, x, x + width, y, node)
	style^ = old_style
	style.height, style.border_box = old_height, old_border_box
	placed = display_range_end(b, placed)

	// only bottom: the element is moved up so that it ends there
	if !set[.Top] && set[.Bottom] {
		dy := cb.y + cb.height - offset[.Bottom] - bottom
		shift_items(b, placed, dy)
		bottom += dy
	}
	add_positioned(b, placed.first_box, placed.end_box)
	b.overflow = max(b.overflow, bottom)
}

// Positioned elements are drawn on top of the normal flow (in document order,
// like z-index: auto). Their boxes are collected here; inner ranges are
// part of an outer one, which ends later.
@(private)
add_positioned :: proc(b: ^Builder, first, end: int) {
	if first == end {
		return
	}
	for len(b.positioned) > 0 && b.positioned[len(b.positioned) - 1][0] >= first {
		pop(&b.positioned)
	}
	append(&b.positioned, [2]int{first, end})
}

// Moves the boxes of positioned elements to the end of the box list. Text and
// images are drawn after all boxes anyway.
@(private)
draw_positioned_last :: proc(b: ^Builder) {
	if len(b.positioned) == 0 {
		return
	}
	boxes := make([dynamic]Box, 0, len(b.layout.boxes), b.allocator)
	next := 0
	for r in b.positioned {
		append(&boxes, ..b.layout.boxes[next:r[0]])
		next = r[1]
	}
	append(&boxes, ..b.layout.boxes[next:])
	for r in b.positioned {
		append(&boxes, ..b.layout.boxes[r[0]:r[1]])
	}
	b.layout.boxes = boxes
}

// The offset of a position: relative element: left wins over right, top over
// bottom. Percentages of top/bottom would refer to a height that is usually
// not known, so they count as 0.
@(private)
relative_offset :: proc(b: ^Builder, style: dom.Style) -> (offset: [2]f32) {
	if style.position != .Relative {
		return
	}
	available := b.right - b.left
	resolve :: proc(b: ^Builder, style: dom.Style, length: dom.Length, available: f32) -> f32 {
		return dom.resolve_length(length, style.font_size, available, b.viewport)
	}
	if style.offset[.Left].unit != .Auto {
		offset.x = resolve(b, style, style.offset[.Left], available)
	} else if style.offset[.Right].unit != .Auto {
		offset.x = -resolve(b, style, style.offset[.Right], available)
	}
	top, bottom := style.offset[.Top], style.offset[.Bottom]
	if top.unit != .Auto && !dom.has_percent(top) {
		offset.y = resolve(b, style, top, available)
	} else if top.unit == .Auto && bottom.unit != .Auto && !dom.has_percent(bottom) {
		offset.y = -resolve(b, style, bottom, available)
	}
	return
}
