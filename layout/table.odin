package layout

import "core:mem/virtual"
import "core:strconv"
import "core:strings"
import "../dom"

// Tables, the "automatic table layout" of browsers in simplified form:
// 1. collect rows and cells into a grid (colspan; rowspan is not supported).
//    Content directly in a table (or row) that is no row (or cell) gets wrapped
//    into an anonymous row and cell, like the CSS spec says. Wikipedia uses
//    this for images: <figure style="display: table"><a><img></a><figcaption>
// 2. measure every cell twice: with unlimited width (max-content, everything
//    on one line) and with width 0 (min-content, roughly the longest word)
// 3. column widths: the widest min/max of their cells; if the table is wider
//    than its columns' max, those are used; otherwise every column gets its
//    min plus a share of the remaining space, in proportion to (max - min)
// 4. lay out each row: cells in their column width, the row as high as its
//    highest cell, then the content is aligned vertically inside the cell

@(private)
Table_Cell :: struct {
	node:     ^dom.Node,
	col:      int,
	span:     int,
	min, max: f32, // border-box widths
}

@(private)
Table_Row :: struct {
	node:  ^dom.Node,
	cells: [dynamic]Table_Cell,
}

// border-spacing is not parsed yet; this is its default
@(private)
TABLE_SPACING :: f32(2)

@(private)
MAX_CONTENT_WIDTH :: f32(1_000_000)

@(private)
layout_table :: proc(b: ^Builder, node: ^dom.Node) {
	finish_line(b)
	style := node.style
	available := b.right - b.left
	margin, _, border, inset := box_edges(b, style, available)
	spacing := 0 if style.border_collapse else TABLE_SPACING

	// 1. grid
	rows := make([dynamic]Table_Row, context.temp_allocator)
	captions := make([dynamic]^dom.Node, context.temp_allocator)
	collect_rows(node, &rows, &captions)
	columns := 0
	for &row in rows {
		col := 0
		for &cell in row.cells {
			cell.col = col
			col += cell.span
		}
		columns = max(columns, col)
	}

	// 2. measure the cells
	col_min := make([]f32, columns, context.temp_allocator)
	col_max := make([]f32, columns, context.temp_allocator)
	for &row in rows {
		for &cell in row.cells {
			measure_cell(b, &cell, available)
		}
	}
	// single-column cells first, then spanning cells widen their columns if needed
	for row in rows {
		for cell in row.cells {
			if cell.span == 1 {
				col_min[cell.col] = max(col_min[cell.col], cell.min)
				col_max[cell.col] = max(col_max[cell.col], cell.max)
			}
		}
	}
	for row in rows {
		for cell in row.cells {
			if cell.span > 1 {
				widen_span(col_min[cell.col:][:cell.span], cell.min, spacing)
				widen_span(col_max[cell.col:][:cell.span], cell.max, spacing)
			}
		}
	}
	sum_min, sum_max: f32
	for i in 0 ..< columns {
		col_max[i] = max(col_max[i], col_min[i])
		sum_min += col_min[i]
		sum_max += col_max[i]
	}

	// 3. table width and column widths
	total_spacing := spacing * f32(columns + 1)
	content_width: f32
	if style.width.unit != .Auto {
		content_width = dom.resolve_length(style.width, style.font_size, available, b.viewport) - inset[.Left] - inset[.Right]
	} else {
		content_width = min(available - margin[.Left] - margin[.Right] - inset[.Left] - inset[.Right], sum_max + total_spacing)
	}
	if style.max_width.unit != .Auto {
		content_width = min(content_width, dom.resolve_length(style.max_width, style.font_size, available, b.viewport))
	}
	content_width = max(content_width, sum_min + total_spacing) // a table never gets narrower than its content

	widths := make([]f32, columns, context.temp_allocator)
	for_columns := content_width - total_spacing
	switch {
	case for_columns >= sum_max:
		// everything fits; extra space (an explicit table width) goes to the
		// columns in proportion to their size
		extra := for_columns - sum_max
		for i in 0 ..< columns {
			share := col_max[i] / sum_max if sum_max > 0 else 1 / f32(columns)
			widths[i] = col_max[i] + extra * share
		}
	case sum_max > sum_min:
		t := (for_columns - sum_min) / (sum_max - sum_min)
		for i in 0 ..< columns {
			widths[i] = col_min[i] + (col_max[i] - col_min[i]) * t
		}
	case:
		copy(widths, col_min)
	}

	// horizontal position, auto margins center the table like a block
	box_width := inset[.Left] + content_width + inset[.Right]
	free := available - box_width - margin[.Left] - margin[.Right]
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
	col_x := make([]f32, columns + 1, context.temp_allocator)
	col_x[0] = content_left + spacing
	for i in 0 ..< columns {
		col_x[i + 1] = col_x[i] + widths[i] + spacing
	}

	// 4. rows. A table is its own block formatting context: margins outside it
	// collapse with each other, but not with anything inside.
	add_margin(b, margin[.Top])
	flush_margin(b)
	table_top := b.y
	table_box := reserve_box(b, style, border)

	y := table_top + inset[.Top]
	for caption in captions {
		if !caption.style.caption_bottom {
			y = layout_cell_contents(b, caption, content_left, content_left + content_width, y)
		}
	}
	y += spacing

	for row in rows {
		if row.node.style.display == .None {
			continue
		}
		row_box := reserve_box(b, row.node.style, {})
		row_top := y

		// what one cell added to the display list: [first, end) per list
		Placed :: struct {
			box_index:            int,
			x, width, height:     f32,
			first_run, end_run:   int,
			first_image, end_image: int,
			first_box, end_box:   int,
		}
		placed := make([dynamic]Placed, context.temp_allocator)
		row_height: f32 = 0

		for cell in row.cells {
			cell_style := cell.node.style
			x := col_x[cell.col]
			width := col_x[cell.col + cell.span] - spacing - x
			_, _, cell_border, cell_inset := box_edges(b, cell_style, width)

			p := Placed{x = x, width = width}
			p.box_index = reserve_box(b, cell_style, cell_border)
			p.first_run, p.first_image, p.first_box = len(b.layout.runs), len(b.layout.images), len(b.layout.boxes)

			bottom := layout_cell_contents(b, cell.node, x + cell_inset[.Left], x + width - cell_inset[.Right], row_top + cell_inset[.Top])
			p.end_run, p.end_image, p.end_box = len(b.layout.runs), len(b.layout.images), len(b.layout.boxes)
			p.height = bottom + cell_inset[.Bottom] - row_top
			if cell_style.height.unit == .Px {
				p.height = max(p.height, cell_style.height.value)
			}
			row_height = max(row_height, p.height)
			append(&placed, p)
		}

		for p, i in placed {
			cell_style := row.cells[i].node.style
			// vertical-align: move the content down inside the row
			offset: f32
			switch cell_style.vertical_align {
			case .Top:
			case .Middle:
				offset = (row_height - p.height) / 2
			case .Bottom:
				offset = row_height - p.height
			}
			if offset > 0 {
				shift_items(b, p, offset)
			}
			_, _, cell_border, _ := box_edges(b, cell_style, p.width)
			fill_box(b, p.box_index, cell_style, cell_border, p.x, row_top, p.width, row_height)
		}
		fill_box(b, row_box, row.node.style, {}, content_left, row_top, content_width, row_height)
		y = row_top + row_height + spacing
	}

	for caption in captions {
		if caption.style.caption_bottom {
			y = layout_cell_contents(b, caption, content_left, content_left + content_width, y)
		}
	}

	table_bottom := y + inset[.Bottom]
	fill_box(b, table_box, style, border, box_x, table_top, box_width, table_bottom - table_top)

	b.y = table_bottom
	b.x = b.left
	add_margin(b, margin[.Bottom])
}

// Rows of a table in order: directly in the table or inside thead/tbody/tfoot.
// Captions are collected separately. Other content is wrapped into anonymous
// rows/cells (consecutive pieces together), whitespace-only text is dropped.
@(private)
collect_rows :: proc(node: ^dom.Node, rows: ^[dynamic]Table_Row, captions: ^[dynamic]^dom.Node) {
	loose := make([dynamic]^dom.Node, context.temp_allocator) // content waiting for an anonymous row
	flush_loose :: proc(node: ^dom.Node, rows: ^[dynamic]Table_Row, loose: ^[dynamic]^dom.Node) {
		if len(loose) == 0 {
			return
		}
		row := Table_Row{node = anonymous_box(node, .Table_Row, nil)}
		row.cells.allocator = context.temp_allocator
		append(&row.cells, Table_Cell{node = anonymous_box(node, .Table_Cell, loose[:]), span = 1})
		append(rows, row)
		loose^ = make([dynamic]^dom.Node, context.temp_allocator)
	}

	for child in node.children {
		if is_blank(child) {
			continue
		}
		display := child.style.display if child.kind == .Element else dom.Display.Inline
		#partial switch display {
		case .None:
		case .Table_Row_Group:
			flush_loose(node, rows, &loose)
			collect_rows(child, rows, captions)
		case .Table_Row:
			flush_loose(node, rows, &loose)
			append(rows, collect_cells(child))
		case .Table_Caption:
			flush_loose(node, rows, &loose)
			append(captions, child)
		case:
			append(&loose, child)
		}
	}
	flush_loose(node, rows, &loose)
}

@(private)
collect_cells :: proc(row_node: ^dom.Node) -> Table_Row {
	row := Table_Row{node = row_node}
	row.cells.allocator = context.temp_allocator
	loose := make([dynamic]^dom.Node, context.temp_allocator)
	for cell in row_node.children {
		if is_blank(cell) {
			continue
		}
		if cell.kind == .Element && cell.style.display == .Table_Cell {
			if len(loose) > 0 {
				append(&row.cells, Table_Cell{node = anonymous_box(row_node, .Table_Cell, loose[:]), span = 1})
				loose = make([dynamic]^dom.Node, context.temp_allocator)
			}
			span := 1
			if text, ok := dom.attribute(cell, "colspan"); ok {
				if n, parsed := strconv.parse_int(text); parsed && n > 1 {
					span = min(n, 1000)
				}
			}
			append(&row.cells, Table_Cell{node = cell, span = span})
		} else if cell.kind != .Comment && !(cell.kind == .Element && cell.style.display == .None) {
			append(&loose, cell)
		}
	}
	if len(loose) > 0 {
		append(&row.cells, Table_Cell{node = anonymous_box(row_node, .Table_Cell, loose[:]), span = 1})
	}
	return row
}

// A node that exists only for the layout: it holds children of another node
// without becoming their parent. Its style is inherited from that node, with
// no box properties of its own. Lives in the temp allocator.
@(private)
anonymous_box :: proc(parent: ^dom.Node, display: dom.Display, children: []^dom.Node) -> ^dom.Node {
	node := new(dom.Node, context.temp_allocator)
	node.kind = .Element
	node.tag = ""
	node.style = dom.default_style("", false, parent.style)
	node.style.display = display
	node.children = make([dynamic]^dom.Node, len(children), context.temp_allocator)
	copy(node.children[:], children)
	return node
}

// Whitespace-only text and comments, which a table ignores.
@(private)
is_blank :: proc(node: ^dom.Node) -> bool {
	switch node.kind {
	case .Comment:
		return true
	case .Text:
		return strings.trim_space(node.text) == ""
	case .Document, .Element:
	}
	return false
}

// min/max-content width of a cell, including its padding and border. A width
// set on the cell counts as a minimum.
@(private)
measure_cell :: proc(b: ^Builder, cell: ^Table_Cell, available: f32) {
	style := cell.node.style
	_, _, _, inset := box_edges(b, style, available)
	extra := inset[.Left] + inset[.Right]
	cell.min = measure_contents(b, cell.node, 0) + extra
	cell.max = measure_contents(b, cell.node, MAX_CONTENT_WIDTH) + extra
	if style.width.unit == .Px || style.width.unit == .Em {
		w := dom.resolve_length(style.width, style.font_size, available, b.viewport) + extra
		cell.min = max(cell.min, w)
		cell.max = max(cell.max, w)
	}
}

// A cell spanning several columns: if those are together narrower than the
// cell needs, the difference is spread evenly over them.
@(private)
widen_span :: proc(cols: []f32, needed, spacing: f32) {
	have := spacing * f32(len(cols) - 1)
	for c in cols {
		have += c
	}
	if needed > have {
		extra := (needed - have) / f32(len(cols))
		for &c in cols {
			c += extra
		}
	}
}

// How wide the content of node becomes when laid out in the given width:
// a trial layout into a throwaway arena, only its extent is kept.
@(private)
measure_contents :: proc(b: ^Builder, node: ^dom.Node, width: f32) -> f32 {
	return measure(b, node, width, nil)
}

// A trial layout of root (or, without root, of the children of node).
@(private)
measure :: proc(b: ^Builder, node: ^dom.Node, width: f32, root: ^dom.Node) -> f32 {
	scratch: Layout
	if virtual.arena_init_growing(&scratch.arena) != nil {
		return 0
	}
	defer virtual.arena_destroy(&scratch.arena)
	allocator := virtual.arena_allocator(&scratch.arena)
	scratch.runs.allocator = allocator
	scratch.boxes.allocator = allocator
	scratch.images.allocator = allocator

	trial := Builder {
		layout      = &scratch,
		allocator   = allocator,
		measure     = b.measure,
		left        = 0,
		right       = width,
		line_right  = width,
		viewport    = b.viewport,
		image_sizes = b.image_sizes,
		measuring   = true,
		unfloat     = root,
	}
	trial.line.allocator = allocator
	trial.line_images.allocator = allocator
	trial.block_tops.allocator = allocator
	trial.floats.allocator = allocator

	if root != nil {
		layout_node(&trial, root)
	} else {
		for child in node.children {
			layout_node(&trial, child)
		}
	}
	finish_line(&trial)
	extent := trial.extent
	for f in trial.floats {
		extent = max(extent, f.x + f.width)
	}
	return extent
}

// Lays out the children of a cell (or caption) between left and right,
// starting at top; returns where the content ends. A cell is its own block
// formatting context: no margin collapses out of it, floats stay inside.
@(private)
layout_cell_contents :: proc(b: ^Builder, node: ^dom.Node, left, right, top: f32) -> (bottom: f32) {
	return layout_in_own_context(b, node, left, right, top)
}

// Moves what one cell added to the display list down (vertical-align). Only
// its own range: the cells after it are already in the lists too.
@(private)
shift_items :: proc(b: ^Builder, p: $T, dy: f32) {
	for &run in b.layout.runs[p.first_run:p.end_run] {
		run.y += dy
	}
	for &image in b.layout.images[p.first_image:p.end_image] {
		image.y += dy
	}
	for &box in b.layout.boxes[p.first_box:p.end_box] {
		box.y += dy
	}
}

// Margins, padding, border and their sum (inset) of a box, in px.
@(private)
box_edges :: proc(b: ^Builder, style: dom.Style, available: f32) -> (margin, padding, border, inset: [dom.Edge]f32) {
	for edge in dom.Edge {
		margin[edge] = dom.resolve_length(style.margin[edge], style.font_size, available, b.viewport)
		padding[edge] = dom.resolve_length(style.padding[edge], style.font_size, available, b.viewport)
		border[edge] = dom.border_width_px(style.border[edge], style.font_size, b.viewport)
		inset[edge] = padding[edge] + border[edge]
	}
	return
}

// Reserves a slot in the box list if the style draws anything (background or
// border), so parents come before children. -1 if there is nothing to draw.
@(private)
reserve_box :: proc(b: ^Builder, style: dom.Style, border: [dom.Edge]f32) -> int {
	has_border := border[.Top] > 0 || border[.Right] > 0 || border[.Bottom] > 0 || border[.Left] > 0
	if (style.background[3] == 0 && !has_border) || style.visibility != .Visible {
		return -1
	}
	append(&b.layout.boxes, Box{})
	return len(b.layout.boxes) - 1
}

@(private)
fill_box :: proc(b: ^Builder, index: int, style: dom.Style, border: [dom.Edge]f32, x, y, width, height: f32) {
	if index < 0 {
		return
	}
	box := Box{x, y, width, height, style.background, border, {}}
	for edge in dom.Edge {
		box.border_color[edge] = dom.border_color(style.border[edge], style.color)
	}
	b.layout.boxes[index] = box
	b.extent = max(b.extent, x + width) // a table measures as wide as its box
}
