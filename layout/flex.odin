package layout

import "core:slice"
import "../dom"

// Flexbox, the core of the algorithm from the CSS spec, simplified:
// 1. the children are the items (loose text becomes an anonymous item)
// 2. base size of each item along the main axis: flex-basis, else width,
//    else its content (max-content, measured with a trial layout)
// 3. with flex-wrap, items are broken into lines that fit
// 4. per line, free space is shared by flex-grow; missing space is taken
//    away in proportion to flex-shrink * base size, but not below min-content
// 5. justify-content places what is left, then each item is laid out at its
//    position as its own block
// 6. cross axis: a line is as high as its highest item; align-items /
//    align-self move items down or stretch their box to the line height
// Columns are simpler: items one below the other with the gap and their
// cross alignment (justify-content would need a container height).

@(private)
Flex_Item :: struct {
	node:            ^dom.Node,
	margin:          [dom.Edge]f32,
	inset:           [dom.Edge]f32,
	base, min_size:  f32, // main size of the border box (without margins)
	size:            f32, // after growing/shrinking
	height:          f32, // laid out, including margins
	using drawn:     Display_Range, // what the item added to the display list
}

@(private)
layout_flex :: proc(b: ^Builder, node: ^dom.Node) {
	finish_line(b)
	style := node.style
	flex := style.flex
	available := b.right - b.left
	margin, _, border, inset := box_edges(b, style, available)
	column := flex.direction == .Column || flex.direction == .Column_Reverse

	items := collect_flex_items(node)
	if flex.direction == .Row_Reverse || flex.direction == .Column_Reverse {
		slice.reverse(items[:])
	}

	// container width like a block's
	inset_x := inset[.Left] + inset[.Right]
	width, has_width := specified_width(b, style, available, inset_x)
	if !has_width {
		width = available - margin[.Left] - margin[.Right] - inset_x
	}
	width = clamp_width(b, style, available, inset_x, width)

	main_gap := dom.resolve_length(flex.row_gap if column else flex.column_gap, style.font_size, width, b.viewport)
	cross_gap := dom.resolve_length(flex.column_gap if column else flex.row_gap, style.font_size, width, b.viewport)

	for &item in items {
		measure_flex_item(b, &item, width, column)
	}

	// in a trial layout the container must not take the whole "infinite"
	// width, but only what its items need
	if b.measuring && style.width.unit == .Auto {
		natural: f32 = 0
		for item, i in items {
			outer := item.base + item.margin[.Left] + item.margin[.Right]
			if column {
				natural = max(natural, outer)
			} else {
				natural += outer + (main_gap if i > 0 else 0)
			}
		}
		width = min(width, natural)
	}

	free := available - width - inset[.Left] - inset[.Right] - margin[.Left] - margin[.Right]
	if free > 0 {
		left_auto := style.margin[.Left].unit == .Auto
		right_auto := style.margin[.Right].unit == .Auto
		if left_auto && right_auto {
			margin[.Left] += free / 2
		} else if left_auto {
			margin[.Left] += free
		}
	}
	box_x := b.left + margin[.Left]
	content_left := box_x + inset[.Left]

	// a flex container is its own formatting context, like a table
	add_margin(b, margin[.Top])
	flush_margin(b)
	top := b.y
	box_index := reserve_box(b, style, border)

	y := top + inset[.Top]
	// absolute and fixed children are no items; their static position is the
	// start of the content box
	for child in node.children {
		if child.kind != .Element || child.style.display == .None {
			continue
		}
		#partial switch child.style.position {
		case .Absolute:
			wait_for_containing_block(b, child, {content_left, y})
		case .Fixed:
			if !b.measuring {
				append(&b.fixed_waiting, Waiting_Absolute{child, {content_left, y}})
			}
		}
	}
	if column {
		y = layout_flex_column(b, node, items[:], content_left, width, y, main_gap)
	} else {
		y = layout_flex_rows(b, node, items[:], content_left, width, y, main_gap, cross_gap)
	}

	bottom := y + inset[.Bottom]
	fill_box(b, box_index, style, border, box_x, top, inset[.Left] + width + inset[.Right], bottom - top)
	b.y = bottom
	b.x = b.left
	add_margin(b, margin[.Bottom])
}

@(private)
layout_flex_rows :: proc(b: ^Builder, container: ^dom.Node, items: []Flex_Item, left, width, top, gap, line_gap: f32) -> (bottom: f32) {
	flex := container.style.flex
	y := top

	// 3. lines
	lines := make([dynamic][]Flex_Item, context.temp_allocator)
	start := 0
	used: f32 = 0
	for item, i in items {
		outer := item.base + item.margin[.Left] + item.margin[.Right]
		if flex.wrap && i > start && used + gap + outer > width {
			append(&lines, items[start:i])
			start = i
			used = 0
		}
		used += outer + (gap if i > start else 0)
	}
	if start < len(items) {
		append(&lines, items[start:])
	}

	for line, line_index in lines {
		if line_index > 0 {
			y += line_gap
		}
		// 4. grow or shrink
		used = gap * f32(len(line) - 1)
		total_grow, total_shrink: f32
		for item in line {
			used += item.base + item.margin[.Left] + item.margin[.Right]
			total_grow += item.node.style.flex.grow
			total_shrink += item.node.style.flex.shrink * item.base
		}
		free := width - used
		for &item in line {
			item.size = item.base
			grow, shrink := item.node.style.flex.grow, item.node.style.flex.shrink
			if free > 0 && total_grow > 0 {
				item.size += free * grow / total_grow
			} else if free < 0 && total_shrink > 0 {
				item.size = max(item.base + free * shrink * item.base / total_shrink, item.min_size)
			}
		}

		// 5. justify-content with what is left
		remaining := width - gap * f32(len(line) - 1)
		for item in line {
			remaining -= item.size + item.margin[.Left] + item.margin[.Right]
		}
		offset, between := justify_offsets(flex.justify, max(remaining, 0), len(line))

		x := left + offset
		line_height: f32 = 0
		for &item in line {
			outer := item.margin[.Left] + item.size + item.margin[.Right]
			lay_out_flex_item(b, &item, x, outer, y, item.size)
			line_height = max(line_height, item.height)
			x += outer + gap + between
		}

		// 6. cross axis
		for &item in line {
			align_flex_item(b, &item, container, line_height)
		}
		y += line_height
	}
	return y
}

@(private)
layout_flex_column :: proc(b: ^Builder, container: ^dom.Node, items: []Flex_Item, left, width, top, gap: f32) -> (bottom: f32) {
	y := top
	for &item, i in items {
		if i > 0 {
			y += gap
		}
		align := cross_alignment(item.node, container)
		outer := width
		if align != .Stretch && item.node.style.width.unit == .Auto {
			// shrink-to-fit, like a float: its content size, at most the width
			outer = max(min(item.base, width), item.min_size) + item.margin[.Left] + item.margin[.Right]
		}
		x := left
		switch align {
		case .Center:
			x += (width - outer) / 2
		case .End:
			x += width - outer
		case .Start, .Stretch:
		}
		lay_out_flex_item(b, &item, x, outer, y, -1)
		y += item.height
	}
	return y
}

// Lays out one item at x (its margin box is outer wide) and remembers what it
// added to the display list. main_size >= 0 forces the width of its border box.
@(private)
lay_out_flex_item :: proc(b: ^Builder, item: ^Flex_Item, x, outer, top, main_size: f32) {
	item.drawn = display_range_start(b)

	// the grown/shrunk size wins over a width set on the item (as a content
	// width, so for the moment it is content-box)
	style := &item.node.style
	old_width, old_border_box := style.width, style.border_box
	if main_size >= 0 {
		style.width = dom.px(max(main_size - item.inset[.Left] - item.inset[.Right], 0))
		style.border_box = false
	}
	bottom := layout_in_own_context(b, item.node, x, x + outer, top, item.node)
	style.width, style.border_box = old_width, old_border_box

	item.height = bottom - top
	item.drawn = display_range_end(b, item.drawn)
}

// align-items / align-self on the cross axis of a row.
@(private)
align_flex_item :: proc(b: ^Builder, item: ^Flex_Item, container: ^dom.Node, line_height: f32) {
	offset: f32
	switch cross_alignment(item.node, container) {
	case .Start:
	case .Center:
		offset = (line_height - item.height) / 2
	case .End:
		offset = line_height - item.height
	case .Stretch:
		// the item's own box (background/border) grows to the line height;
		// it is the first box the item added, if it has one
		style := item.node.style
		has_border := style.border[.Top].style != .None || style.border[.Bottom].style != .None ||
			style.border[.Left].style != .None || style.border[.Right].style != .None
		if (style.background[3] > 0 || has_border) && item.first_box < item.end_box {
			b.layout.boxes[item.first_box].height = line_height - item.margin[.Top] - item.margin[.Bottom]
		}
	}
	if offset > 0 {
		shift_items(b, item.drawn, offset)
	}
}

@(private)
cross_alignment :: proc(item, container: ^dom.Node) -> dom.Align {
	self := item.style.flex.align_self
	if self == .Auto {
		return container.style.flex.align_items
	}
	return dom.Align(int(self) - 1)
}

// Where the first item starts and the extra space between items.
@(private)
justify_offsets :: proc(justify: dom.Justify, remaining: f32, count: int) -> (offset, between: f32) {
	switch justify {
	case .Start:
	case .End:
		offset = remaining
	case .Center:
		offset = remaining / 2
	case .Space_Between:
		if count > 1 {
			between = remaining / f32(count - 1)
		}
	case .Space_Around:
		between = remaining / f32(count)
		offset = between / 2
	case .Space_Evenly:
		between = remaining / f32(count + 1)
		offset = between
	}
	return
}

// Base size (flex-basis, width or max-content) and min-content of an item.
@(private)
measure_flex_item :: proc(b: ^Builder, item: ^Flex_Item, container_width: f32, column: bool) {
	style := item.node.style
	item.margin, _, _, item.inset = box_edges(b, style, container_width)
	extra := item.inset[.Left] + item.inset[.Right]

	// trial layouts give the right edge of the content, which already
	// includes the left margin and inset
	content_max := measure_node(b, item.node, MAX_CONTENT_WIDTH) - item.margin[.Left] + item.inset[.Right]
	content_min := measure_node(b, item.node, 0) - item.margin[.Left] + item.inset[.Right]

	// base and min size are border box sizes; box-sizing decides what
	// flex-basis and width mean
	switch {
	case !column && style.flex.basis.unit != .Auto:
		item.base = content_size(b, style, style.flex.basis, container_width, extra) + extra
	case style.width.unit != .Auto:
		item.base = content_size(b, style, style.width, container_width, extra) + extra
	case:
		item.base = content_max
	}
	// min-width: auto - an item doesn't shrink below its content
	item.min_size = min(max(content_min, 0), item.base) if style.width.unit != .Auto else max(content_min, 0)
	if style.min_width.unit != .Auto && !dom.is_zero(style.min_width) {
		item.min_size = content_size(b, style, style.min_width, container_width, extra) + extra
	}
	item.base = max(item.base, 0)
}

// The items of a flex container; loose text becomes an anonymous item.
@(private)
collect_flex_items :: proc(node: ^dom.Node) -> [dynamic]Flex_Item {
	items := make([dynamic]Flex_Item, context.temp_allocator)
	loose := make([dynamic]^dom.Node, context.temp_allocator)
	flush :: proc(node: ^dom.Node, items: ^[dynamic]Flex_Item, loose: ^[dynamic]^dom.Node) {
		if len(loose) > 0 {
			append(items, Flex_Item{node = anonymous_box(node, .Block, loose[:])})
			loose^ = make([dynamic]^dom.Node, context.temp_allocator)
		}
	}
	for child in node.children {
		if is_blank(child) {
			continue
		}
		if child.kind == .Text {
			append(&loose, child)
			continue
		}
		style := child.style
		if style.display == .None || style.position == .Absolute || style.position == .Fixed {
			continue
		}
		flush(node, &items, &loose)
		append(&items, Flex_Item{node = child})
	}
	flush(node, &items, &loose)
	return items
}
