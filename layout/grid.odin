package layout

import "../dom"

// CSS grid, simplified from the spec's algorithm:
// 1. the children are the items (loose text becomes an anonymous item), each
//    measured like a flex item (min-content and max-content width)
// 2. placement: items with lines or an area name go there; the others fill
//    the free cells row by row (grid-auto-flow: row, sparse). Rows and
//    columns beyond the template are added (implicit tracks).
// 3. column widths: fixed sizes first; auto, min-content and max-content
//    tracks get what the items in them need (items spanning several tracks
//    share their need equally) and grow up to their max-content; fr tracks
//    share what is left; without fr tracks, auto tracks take the rest
// 4. rows from top to bottom: the items starting in a row are laid out at
//    their cell's width; a row is as high as its highest item (or its
//    fixed size), an item spanning rows makes its last row higher
// 5. alignment in the cell: justify-items/-self (horizontal: stretch or
//    shrink-to-fit and moved), align-items/-self (vertical, like flexbox)
// Not yet: fr rows (a container height), dense packing, grid-auto-flow:
// column, order, baseline alignment.

@(private)
Grid_Item :: struct {
	using flex:  Flex_Item, // node, margins, sizes, what it drew (shared with flexbox)
	column, row: [2]int,    // the tracks it covers: [start, end), 0-based
}

@(private)
Track_Sizing :: struct {
	base, limit: f32, // the size so far and how far it may grow
	fr:          f32, // > 0: a flexible track
	stretches:   bool, // max is auto: takes free space when there are no fr tracks
}

@(private)
layout_grid :: proc(b: ^Builder, node: ^dom.Node) {
	finish_line(b)
	style := node.style
	available := b.right - b.left
	margin, _, border, inset := box_edges(b, style, available)

	// container width like a block's
	inset_x := inset[.Left] + inset[.Right]
	width, has_width := specified_width(b, style, available, inset_x)
	if !has_width {
		width = available - margin[.Left] - margin[.Right] - inset_x
	}
	width = max(clamp_width(b, style, available, inset_x, width), 0)
	column_gap := dom.resolve_length(style.flex.column_gap, style.font_size, width, b.viewport)
	row_gap := dom.resolve_length(style.flex.row_gap, style.font_size, width, b.viewport)

	flex_items := collect_flex_items(node)
	items := make([]Grid_Item, len(flex_items), context.temp_allocator)
	for fi, i in flex_items {
		items[i].flex = fi
		measure_flex_item(b, &items[i].flex, width, false)
	}

	columns := explicit_columns(b, style, width, column_gap)
	rows := style.grid.rows
	column_count, row_count := place_grid_items(items, style.grid, len(columns), max(len(rows), area_rows(style.grid)))
	columns = extend_tracks(columns, column_count, style.grid.auto_columns)
	rows = extend_tracks(rows, row_count, style.grid.auto_rows)

	// in a trial layout the container must not take the whole "infinite"
	// width, but only what its tracks need
	if b.measuring && style.width.unit == .Auto {
		width = min(width, natural_grid_width(b, style, columns, items, column_gap))
	}
	sizes := size_columns(b, style, columns, items, width, column_gap)

	free := available - width - inset_x - margin[.Left] - margin[.Right]
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

	// a grid container is its own formatting context, like a table
	add_margin(b, margin[.Top])
	flush_margin(b)
	top := b.y
	box_index := reserve_box(b, style, border)
	y := top + inset[.Top]
	register_out_of_flow_children(b, node, content_left, y)

	y = layout_grid_rows(b, node, items, rows, sizes, content_left, y, column_gap, row_gap)

	if b.measuring {
		// the right edge of the tracks, also when the items don't reach it
		used := column_gap * f32(max(len(sizes) - 1, 0))
		for size in sizes {
			used += size
		}
		b.extent = max(b.extent, content_left + used)
	}
	bottom := y + inset[.Bottom]
	fill_box(b, box_index, style, border, box_x, top, inset_x + width, bottom - top)
	b.y = bottom
	b.x = b.left
	add_margin(b, margin[.Bottom])
}

// The template's columns, with repeat(auto-fill, ...) repeated as often as
// it fits into the width.
@(private)
explicit_columns :: proc(b: ^Builder, style: dom.Style, width, gap: f32) -> []dom.Track {
	g := style.grid
	if len(g.auto_repeat.tracks) == 0 {
		return g.columns
	}
	fixed :: proc(b: ^Builder, t: dom.Track, style: dom.Style, width: f32) -> f32 {
		// the size a repeated track needs at least: its fixed max, else its fixed min
		if t.max.kind == .Length {
			return dom.resolve_length(t.max.length, style.font_size, width, b.viewport)
		}
		if t.min.kind == .Length {
			return dom.resolve_length(t.min.length, style.font_size, width, b.viewport)
		}
		return 0
	}
	others: f32 = 0
	for t in g.columns {
		others += fixed(b, t, style, width) + gap
	}
	repeat: f32 = 0
	for t in g.auto_repeat.tracks {
		repeat += fixed(b, t, style, width) + gap
	}
	count := 1
	if repeat > 0 {
		count = max(int((width - others + gap) / repeat), 1)
	}
	count = min(count, 100)
	result := make([dynamic]dom.Track, 0, len(g.columns) + count * len(g.auto_repeat.tracks), context.temp_allocator)
	append(&result, ..g.columns[:g.auto_repeat.at])
	for _ in 0 ..< count {
		append(&result, ..g.auto_repeat.tracks)
	}
	append(&result, ..g.columns[g.auto_repeat.at:])
	return result[:]
}

@(private)
area_rows :: proc(g: dom.Grid) -> int {
	rows := 0
	for area in g.areas {
		rows = max(rows, area.row_end - 1)
	}
	return rows
}

// The tracks, plus implicit ones up to count.
@(private)
extend_tracks :: proc(tracks: []dom.Track, count: int, implicit: dom.Track) -> []dom.Track {
	if count <= len(tracks) {
		return tracks
	}
	result := make([]dom.Track, count, context.temp_allocator)
	copy(result, tracks)
	for i in len(tracks) ..< count {
		result[i] = implicit
	}
	return result
}

// Places the items into cells; returns how many columns and rows there are.
@(private)
place_grid_items :: proc(items: []Grid_Item, g: dom.Grid, explicit_columns, explicit_rows: int) -> (columns, rows: int) {
	columns = max(explicit_columns, 1)
	rows = explicit_rows
	Axis :: struct {
		start, end: int,
		definite:   bool,
		span:       int,
	}
	resolve :: proc(p: dom.Grid_Placement, explicit: int, areas: []dom.Grid_Area, is_row: bool) -> (a: Axis) {
		// a line as a track index: 1 is the first line, -1 the last explicit one
		line :: proc(l: dom.Grid_Line, explicit: int, areas: []dom.Grid_Area, is_row, is_end: bool) -> (int, bool) {
			switch l.kind {
			case .Line:
				if l.value > 0 {
					return l.value - 1, true
				}
				return max(explicit + 1 + l.value, 0), true
			case .Name:
				for area in areas {
					if area.name == l.name {
						if is_row {
							return (area.row_end if is_end else area.row_start) - 1, true
						}
						return (area.column_end if is_end else area.column_start) - 1, true
					}
				}
			case .Auto, .Span:
			}
			return 0, false
		}
		s, has_s := line(p.start, explicit, areas, is_row, false)
		e, has_e := line(p.end, explicit, areas, is_row, true)
		span := 1
		if p.start.kind == .Span {
			span = p.start.value
		} else if p.end.kind == .Span {
			span = p.end.value
		}
		switch {
		case has_s && has_e:
			if e < s {
				s, e = e, s
			}
			if e == s {
				e = s + 1
			}
			return {s, e, true, e - s}
		case has_s:
			return {s, s + span, true, span}
		case has_e:
			s = max(e - span, 0)
			return {s, max(e, s + 1), true, max(e, s + 1) - s}
		}
		return {span = span}
	}

	// cells taken so far: row by row, one bool per column
	taken := make([dynamic][]bool, context.temp_allocator)
	occupied :: proc(taken: ^[dynamic][]bool, r, c: int) -> bool {
		return r < len(taken) && c < len(taken[r]) && taken[r][c]
	}
	take :: proc(taken: ^[dynamic][]bool, item: ^Grid_Item) {
		for r in item.row[0] ..< item.row[1] {
			for len(taken) <= r {
				append(taken, make([]bool, 0, context.temp_allocator))
			}
			if len(taken[r]) < item.column[1] {
				wider := make([]bool, item.column[1], context.temp_allocator)
				copy(wider, taken[r])
				taken[r] = wider
			}
			for c in item.column[0] ..< item.column[1] {
				taken[r][c] = true
			}
		}
	}
	fits :: proc(taken: ^[dynamic][]bool, r, c, rows, columns: int) -> bool {
		for rr in r ..< r + rows {
			for cc in c ..< c + columns {
				if occupied(taken, rr, cc) {
					return false
				}
			}
		}
		return true
	}

	// 1. items placed on both axes, 2. with a row, 3. the rest in order
	cols := make([]Axis, len(items), context.temp_allocator)
	rws := make([]Axis, len(items), context.temp_allocator)
	for &item, i in items {
		cols[i] = resolve(item.node.style.grid.column, explicit_columns, g.areas, false)
		rws[i] = resolve(item.node.style.grid.row, explicit_rows, g.areas, true)
		if cols[i].definite {
			columns = max(columns, cols[i].end)
		} else {
			columns = max(columns, cols[i].span)
		}
		if cols[i].definite && rws[i].definite {
			item.column, item.row = {cols[i].start, cols[i].end}, {rws[i].start, rws[i].end}
			take(&taken, &item)
		}
	}
	for &item, i in items {
		if rws[i].definite && !cols[i].definite {
			c := 0
			for !fits(&taken, rws[i].start, c, rws[i].span, cols[i].span) && c + cols[i].span < columns {
				c += 1
			}
			item.column, item.row = {c, c + cols[i].span}, {rws[i].start, rws[i].end}
			take(&taken, &item)
		}
	}
	cursor_r, cursor_c := 0, 0
	for &item, i in items {
		if rws[i].definite {
			continue
		}
		span_c, span_r := min(cols[i].span, columns), rws[i].span
		if cols[i].definite {
			// a fixed column: the first free row from the cursor on
			if cols[i].start < cursor_c {
				cursor_r += 1
			}
			for !fits(&taken, cursor_r, cols[i].start, span_r, cols[i].end - cols[i].start) {
				cursor_r += 1
			}
			cursor_c = cols[i].start
			item.column, item.row = {cols[i].start, cols[i].end}, {cursor_r, cursor_r + span_r}
		} else {
			for {
				if cursor_c + span_c > columns {
					cursor_r, cursor_c = cursor_r + 1, 0
					continue
				}
				if fits(&taken, cursor_r, cursor_c, span_r, span_c) {
					break
				}
				cursor_c += 1
			}
			item.column, item.row = {cursor_c, cursor_c + span_c}, {cursor_r, cursor_r + span_r}
			cursor_c += span_c
		}
		take(&taken, &item)
	}
	for item in items {
		columns = max(columns, item.column[1])
		rows = max(rows, item.row[1])
	}
	return
}

// What an item needs on the column axis, with its margins: at least
// (min-content) and at most (max-content, or its width).
@(private)
item_contributions :: proc(item: Grid_Item) -> (min_need, max_need: f32) {
	m := item.margin[.Left] + item.margin[.Right]
	return item.min_size + m, max(item.base, item.min_size) + m
}

// Step 3: the widths of the columns.
@(private)
size_columns :: proc(b: ^Builder, style: dom.Style, tracks: []dom.Track, items: []Grid_Item, width, gap: f32) -> []f32 {
	n := len(tracks)
	t := make([]Track_Sizing, n, context.temp_allocator)
	intrinsic_min := make([]bool, n, context.temp_allocator)
	intrinsic_max := make([]bool, n, context.temp_allocator)
	for track, i in tracks {
		if track.min.kind == .Length {
			t[i].base = dom.resolve_length(track.min.length, style.font_size, width, b.viewport)
		} else {
			intrinsic_min[i] = true
		}
		#partial switch track.max.kind {
		case .Length:
			t[i].limit = dom.resolve_length(track.max.length, style.font_size, width, b.viewport)
		case .Fr:
			t[i].fr = track.max.fr
		case:
			intrinsic_max[i] = true
			t[i].stretches = track.max.kind == .Auto
		}
	}

	// what the items in a single track need
	for item in items {
		if item.column[1] - item.column[0] != 1 {
			continue
		}
		i := item.column[0]
		min_need, max_need := item_contributions(item)
		if intrinsic_min[i] {
			t[i].base = max(t[i].base, max_need if tracks[i].min.kind == .Max_Content else min_need)
		}
		if intrinsic_max[i] {
			t[i].limit = max(t[i].limit, min_need if tracks[i].max.kind == .Min_Content else max_need)
		}
	}
	// items over several tracks share what is missing among those tracks
	for item in items {
		span := item.column[1] - item.column[0]
		if span < 2 {
			continue
		}
		min_need, max_need := item_contributions(item)
		have_base, have_limit := gap * f32(span - 1), gap * f32(span - 1)
		growing_min, growing_max := 0, 0
		for i in item.column[0] ..< item.column[1] {
			have_base += t[i].base
			have_limit += max(t[i].limit, t[i].base)
			growing_min += 1 if intrinsic_min[i] else 0
			growing_max += 1 if intrinsic_max[i] else 0
		}
		for i in item.column[0] ..< item.column[1] {
			if intrinsic_min[i] && min_need > have_base {
				t[i].base += (min_need - have_base) / f32(growing_min)
			}
			if intrinsic_max[i] && max_need > have_limit {
				t[i].limit = max(t[i].limit, t[i].base) + (max_need - have_limit) / f32(growing_max)
			}
		}
	}
	for &s in t {
		s.limit = max(s.limit, s.base)
	}

	// grow the tracks that aren't flexible up to their limit, equally
	gaps := gap * f32(max(n - 1, 0))
	free := width - gaps
	for s in t {
		free -= s.base
	}
	for free > 0.01 {
		growing := 0
		for s in t {
			if s.fr == 0 && s.limit > s.base + 0.01 {
				growing += 1
			}
		}
		if growing == 0 {
			break
		}
		share := free / f32(growing)
		for &s in t {
			if s.fr == 0 && s.limit > s.base + 0.01 {
				grow := min(share, s.limit - s.base)
				s.base += grow
				free -= grow
			}
		}
	}

	// fr tracks share what is left (a track that needs more than its share
	// keeps its size and is left out)
	total_fr: f32 = 0
	for s in t {
		total_fr += s.fr
	}
	if total_fr > 0 {
		leftover := width - gaps
		for s in t {
			if s.fr == 0 {
				leftover -= s.base
			}
		}
		flexible := make([]bool, n, context.temp_allocator)
		for s, i in t {
			flexible[i] = s.fr > 0
		}
		for _ in 0 ..< n {
			fr_sum: f32 = 0
			rest := leftover
			for s, i in t {
				if flexible[i] {
					fr_sum += s.fr
				} else if s.fr > 0 {
					rest -= s.base
				}
			}
			if fr_sum <= 0 {
				break
			}
			unit := max(rest, 0) / max(fr_sum, 1)
			changed := false
			for s, i in t {
				if flexible[i] && s.fr * unit < s.base {
					flexible[i] = false
					changed = true
				}
			}
			if !changed {
				for &s, i in t {
					if flexible[i] {
						s.base = s.fr * unit
					}
				}
				break
			}
		}
	} else if free > 0.01 {
		// no fr tracks: auto tracks take what is left
		stretching := 0
		for s in t {
			if s.stretches {
				stretching += 1
			}
		}
		for &s in t {
			if s.stretches {
				s.base += free / f32(stretching)
			}
		}
	}

	sizes := make([]f32, n, context.temp_allocator)
	for s, i in t {
		sizes[i] = s.base
	}
	return sizes
}

// The width the tracks take with max-content items (for a trial layout).
@(private)
natural_grid_width :: proc(b: ^Builder, style: dom.Style, tracks: []dom.Track, items: []Grid_Item, gap: f32) -> f32 {
	n := len(tracks)
	need := make([]f32, n, context.temp_allocator)
	for item in items {
		span := item.column[1] - item.column[0]
		_, max_need := item_contributions(item)
		share := (max_need - gap * f32(span - 1)) / f32(span)
		for i in item.column[0] ..< item.column[1] {
			need[i] = max(need[i], share)
		}
	}
	total := gap * f32(max(n - 1, 0))
	for track, i in tracks {
		size := need[i]
		if track.max.kind == .Length && !dom.has_percent(track.max.length) {
			size = dom.resolve_length(track.max.length, style.font_size, 0, b.viewport)
		} else if track.min.kind == .Length && !dom.has_percent(track.min.length) {
			size = max(size, dom.resolve_length(track.min.length, style.font_size, 0, b.viewport))
		}
		total += size
	}
	return total
}

// Step 4 and 5: rows from top to bottom; returns the bottom of the last row.
@(private)
layout_grid_rows :: proc(b: ^Builder, container: ^dom.Node, items: []Grid_Item, rows: []dom.Track, columns: []f32, left, top, column_gap, row_gap: f32) -> f32 {
	style := container.style
	column_x := make([]f32, len(columns) + 1, context.temp_allocator)
	x := left
	for size, i in columns {
		column_x[i] = x
		x += size + column_gap
	}
	column_x[len(columns)] = x - column_gap

	row_top := make([]f32, len(rows) + 1, context.temp_allocator)
	row_height := make([]f32, len(rows), context.temp_allocator)
	y := top
	for track, r in rows {
		row_top[r] = y
		height: f32 = 0
		if track.min.kind == .Length && !dom.has_percent(track.min.length) {
			height = dom.resolve_length(track.min.length, style.font_size, 0, b.viewport)
		}
		for &item in items {
			if item.row[0] != r {
				continue
			}
			cell_left := column_x[item.column[0]]
			cell_width := column_x[item.column[1]] - column_gap - cell_left
			if item.column[1] == len(columns) {
				cell_width = column_x[item.column[1]] - cell_left
			}
			lay_out_grid_item(b, &item, container, cell_left, cell_width, y)
			if item.row[1] - item.row[0] == 1 {
				height = max(height, item.height)
			}
		}
		// an item over several rows ending here: this row makes up the rest
		for item in items {
			if item.row[1] - 1 == r && item.row[1] - item.row[0] > 1 {
				height = max(height, item.height - (y - row_top[item.row[0]]))
			}
		}
		// a fixed size: the content doesn't change it (what is higher overflows)
		if track.max.kind == .Length && !dom.has_percent(track.max.length) {
			fixed := dom.resolve_length(track.max.length, style.font_size, 0, b.viewport)
			if track.min.kind == .Length && !dom.has_percent(track.min.length) {
				fixed = max(fixed, dom.resolve_length(track.min.length, style.font_size, 0, b.viewport))
			}
			height = fixed
		}
		row_height[r] = height
		y += height
		if r < len(rows) - 1 {
			y += row_gap
		}
	}
	row_top[len(rows)] = y

	// vertical alignment in the cell, like align-items in a flex line
	for &item in items {
		last := item.row[1] - 1
		cell_height := row_top[last] + row_height[last] - row_top[item.row[0]]
		align_flex_item(b, &item.flex, container, cell_height)
	}
	return y
}

// Lays out an item in its cell: stretched to the cell's width, or as wide as
// its content (or width) and moved by justify-self.
@(private)
lay_out_grid_item :: proc(b: ^Builder, item: ^Grid_Item, container: ^dom.Node, cell_left, cell_width, top: f32) {
	align := container.style.grid.justify_items
	if self := item.node.style.grid.justify_self; self != .Auto {
		align = dom.Align(int(self) - 1)
	}
	outer := cell_width
	margins := item.margin[.Left] + item.margin[.Right]
	if item.node.style.width.unit != .Auto {
		outer = item.base + margins
	} else if align != .Stretch {
		// shrink-to-fit, like a float: its content size, at most the cell
		outer = max(min(item.base, cell_width - margins), item.min_size) + margins
	}
	x := cell_left
	switch align {
	case .Center:
		x += (cell_width - outer) / 2
	case .End:
		x += cell_width - outer
	case .Start, .Stretch:
	}
	lay_out_flex_item(b, &item.flex, x, outer, top, -1)
}
