package dom

import "core:strconv"
import "core:strings"

// CSS grid: the properties of a grid container (its tracks and named areas)
// and of its items (where they go). Not inherited. Gaps and align-items /
// align-self are shared with flexbox (Style.flex), justify-* are here.
// Simplified: no line names in track lists (they are skipped), no subgrid,
// grid-auto-flow is always row (dense is ignored).
Grid :: struct {
	// container
	columns, rows:   []Track, // grid-template-columns / -rows: the explicit tracks
	auto_repeat:     Auto_Repeat, // repeat(auto-fill/auto-fit, ...) in the columns
	auto_rows:       Track,   // grid-auto-rows: size of implicit rows (auto)
	auto_columns:    Track,   // grid-auto-columns
	areas:           []Grid_Area, // grid-template-areas
	justify_items:   Align,   // stretch by default (normal)
	// item
	justify_self:    Align_Self,
	column, row:     Grid_Placement, // grid-column / grid-row / grid-area
}

// One track: its size between min and max, like minmax(min, max). A plain
// size is both; 1fr is minmax(auto, 1fr).
Track :: struct {
	min, max: Track_Size,
}

Track_Size :: struct {
	kind:   Track_Kind,
	length: Length, // .Length
	fr:     f32,    // .Fr
}

Track_Kind :: enum {
	Auto, // the zero value: an auto track
	Length,
	Fr,
	Min_Content,
	Max_Content,
}

// repeat(auto-fill, <tracks>) at position `at` of the column list: as many
// repetitions as fit (the layout counts them). auto-fit is treated the same.
Auto_Repeat :: struct {
	tracks: []Track,
	at:     int,
}

// A named area of grid-template-areas, in grid lines (1-based, end exclusive).
Grid_Area :: struct {
	name:                   string,
	row_start, row_end:     int,
	column_start, column_end: int,
}

// grid-column / grid-row: the start and end line of an item on one axis.
Grid_Placement :: struct {
	start, end: Grid_Line,
}

Grid_Line :: struct {
	kind:  Grid_Line_Kind,
	value: int,    // the line (negative: counted from the end) or the span
	name:  string, // .Name: an area's name (its start or end line)
}

Grid_Line_Kind :: enum {
	Auto,
	Line,
	Span,
	Name,
}

@(private)
apply_grid_declaration :: proc(style: ^Style, property, value: string) {
	g := &style.grid
	switch property {
	case "grid-template-columns":
		if value == "none" || value == "initial" {
			g.columns, g.auto_repeat = nil, {}
		} else if tracks, repeat, ok := parse_track_list(value); ok {
			g.columns, g.auto_repeat = tracks, repeat
		}
	case "grid-template-rows":
		if value == "none" || value == "initial" {
			g.rows = nil
		} else if tracks, _, ok := parse_track_list(value); ok {
			g.rows = tracks
		}
	case "grid-template-areas":
		g.areas = parse_grid_areas(value) or_else g.areas
	case "grid-template":
		parse_grid_template(g, value)
	case "grid-auto-rows":
		if tracks, _, ok := parse_track_list(value); ok && len(tracks) > 0 {
			g.auto_rows = tracks[0]
		}
	case "grid-auto-columns":
		if tracks, _, ok := parse_track_list(value); ok && len(tracks) > 0 {
			g.auto_columns = tracks[0]
		}
	case "justify-items":
		if a, ok := parse_align(strings.trim_prefix(value, "legacy ")); ok {
			g.justify_items = a
		} else if value == "normal" || value == "initial" {
			g.justify_items = .Stretch
		}
	case "justify-self":
		if value == "auto" || value == "initial" || value == "normal" {
			g.justify_self = .Auto
		} else if a, ok := parse_align(value); ok {
			g.justify_self = Align_Self(int(a) + 1)
		}
	case "grid-column":
		g.column = parse_grid_placement(value) or_else g.column
	case "grid-row":
		g.row = parse_grid_placement(value) or_else g.row
	case "grid-column-start":
		g.column.start = parse_grid_line(value) or_else g.column.start
	case "grid-column-end":
		g.column.end = parse_grid_line(value) or_else g.column.end
	case "grid-row-start":
		g.row.start = parse_grid_line(value) or_else g.row.start
	case "grid-row-end":
		g.row.end = parse_grid_line(value) or_else g.row.end
	case "grid-area":
		parse_grid_area_property(g, value)
	}
}

// A track list like "200px 1fr", "repeat(3, minmax(0, 1fr))",
// "[full-start] minmax(1em, 1fr) [main-start] auto" (names skipped).
@(private)
parse_track_list :: proc(value: string) -> (tracks: []Track, repeat: Auto_Repeat, ok: bool) {
	result := make([dynamic]Track, context.temp_allocator)
	without_names := strip_line_names(value)
	for word in split_outside_parens(without_names, context.temp_allocator) {
		lower := strings.to_lower(word, context.temp_allocator)
		if strings.has_prefix(lower, "repeat(") && strings.has_suffix(lower, ")") {
			inner := lower[len("repeat("):len(lower) - 1]
			comma := strings.index_byte(inner, ',')
			if comma < 0 {
				return
			}
			count_text := strings.trim_space(inner[:comma])
			inner_tracks, _ := parse_track_list(inner[comma + 1:]) or_return
			if count_text == "auto-fill" || count_text == "auto-fit" {
				repeat = {inner_tracks, len(result)}
				continue
			}
			count := strconv.parse_int(count_text) or_return
			for _ in 0 ..< clamp(count, 0, 1000) {
				append(&result, ..inner_tracks)
			}
			continue
		}
		track := parse_track(lower) or_return
		append(&result, track)
	}
	return result[:], repeat, true
}

// [names] in a track list: we don't use line names.
@(private)
strip_line_names :: proc(value: string) -> string {
	if strings.index_byte(value, '[') < 0 {
		return value
	}
	b := strings.builder_make(context.temp_allocator)
	depth := 0
	for c in value {
		switch {
		case c == '[':
			depth += 1
		case c == ']':
			depth -= 1
			strings.write_byte(&b, ' ')
		case depth == 0:
			strings.write_rune(&b, c)
		}
	}
	return strings.to_string(b)
}

@(private)
parse_track :: proc(word: string) -> (track: Track, ok: bool) {
	if strings.has_prefix(word, "minmax(") && strings.has_suffix(word, ")") {
		inner := word[len("minmax("):len(word) - 1]
		comma := strings.index_byte(inner, ',')
		if comma < 0 {
			return
		}
		track.min = parse_track_size(strings.trim_space(inner[:comma])) or_return
		track.max = parse_track_size(strings.trim_space(inner[comma + 1:])) or_return
		if track.min.kind == .Fr {
			return {}, false // a flexible minimum is invalid
		}
		return track, true
	}
	if strings.has_prefix(word, "fit-content(") {
		// fit-content(x): like auto, at most x; we take auto
		return {}, true
	}
	size := parse_track_size(word) or_return
	track = {size, size}
	if size.kind == .Fr {
		track.min = {} // 1fr is minmax(auto, 1fr)
	}
	return track, true
}

@(private)
parse_track_size :: proc(word: string) -> (size: Track_Size, ok: bool) {
	switch word {
	case "auto":
		return {kind = .Auto}, true
	case "min-content":
		return {kind = .Min_Content}, true
	case "max-content":
		return {kind = .Max_Content}, true
	}
	if strings.has_suffix(word, "fr") {
		fr := strconv.parse_f32(word[:len(word) - 2]) or_return
		return {kind = .Fr, fr = max(fr, 0)}, true
	}
	length := parse_length(word, false) or_return
	return {kind = .Length, length = length}, true
}

// grid-template-areas: one string per row, a name per cell ("." = none):
// "head head" "nav main". Each name must form a rectangle; we take the
// rows and columns it first and last appears in.
@(private)
parse_grid_areas :: proc(value: string) -> (areas: []Grid_Area, ok: bool) {
	if value == "none" || value == "initial" {
		return nil, true
	}
	rows := quoted_strings(value) or_return
	result := make([dynamic]Grid_Area, context.temp_allocator)
	for row, r in rows {
		for name, c in strings.fields(row, context.temp_allocator) {
			if strings.trim_left(name, ".") == "" {
				continue
			}
			lower := strings.to_lower(name, context.temp_allocator)
			found := false
			for &area in result {
				if area.name == lower {
					area.row_end = max(area.row_end, r + 2)
					area.column_end = max(area.column_end, c + 2)
					found = true
					break
				}
			}
			if !found {
				append(&result, Grid_Area{lower, r + 1, r + 2, c + 1, c + 2})
			}
		}
	}
	return result[:], true
}

// The contents of the "..." or '...' strings in a value, in order.
@(private)
quoted_strings :: proc(value: string) -> (strs: []string, ok: bool) {
	result := make([dynamic]string, context.temp_allocator)
	for i := 0; i < len(value); i += 1 {
		if value[i] == '"' || value[i] == '\'' {
			end := strings.index_byte(value[i + 1:], value[i])
			if end < 0 {
				return nil, false
			}
			append(&result, value[i + 1:i + 1 + end])
			i += end + 1
		}
	}
	return result[:], len(result) > 0
}

// grid-template: "<rows> / <columns>", or with areas: '"a b" 40px "c d" / 1fr 2fr'
// (each string a row, optionally followed by that row's size).
@(private)
parse_grid_template :: proc(g: ^Grid, value: string) {
	if value == "none" || value == "initial" {
		g.rows, g.columns, g.areas, g.auto_repeat = nil, nil, nil, {}
		return
	}
	slash := index_outside_quotes(value, '/')
	rows_part := value if slash < 0 else value[:slash]
	columns_part := "" if slash < 0 else value[slash + 1:]
	if strings.index_any(rows_part, "\"'") >= 0 {
		areas, ok := parse_grid_areas(rows_part)
		if !ok {
			return
		}
		// the row sizes after the strings
		sizes := make([dynamic]Track, context.temp_allocator)
		rest := rows_part
		for len(rest) > 0 {
			q := strings.index_any(rest, "\"'")
			if q < 0 {
				break
			}
			end := strings.index_byte(rest[q + 1:], rest[q])
			if end < 0 {
				break
			}
			rest = rest[q + 1 + end + 1:]
			next := strings.index_any(rest, "\"'")
			size_text := strings.trim_space(rest if next < 0 else rest[:next])
			track: Track
			if size_text != "" {
				track = parse_track(strings.to_lower(size_text, context.temp_allocator)) or_else Track{}
			}
			append(&sizes, track)
		}
		g.areas, g.rows = areas, sizes[:]
	} else if rows, _, ok := parse_track_list(strings.trim_space(rows_part)); ok {
		g.rows, g.areas = rows, nil
	}
	if slash >= 0 {
		if columns, repeat, ok := parse_track_list(strings.trim_space(columns_part)); ok {
			g.columns, g.auto_repeat = columns, repeat
		}
	}
}

@(private)
index_outside_quotes :: proc(value: string, c: u8) -> int {
	quote: u8 = 0
	for i in 0 ..< len(value) {
		switch {
		case quote != 0:
			if value[i] == quote {
				quote = 0
			}
		case value[i] == '"' || value[i] == '\'':
			quote = value[i]
		case value[i] == c:
			return i
		}
	}
	return -1
}

// grid-column / grid-row: "<start> [/ <end>]".
@(private)
parse_grid_placement :: proc(value: string) -> (p: Grid_Placement, ok: bool) {
	parts := strings.split(value, "/", context.temp_allocator)
	if len(parts) > 2 {
		return
	}
	p.start = parse_grid_line(parts[0]) or_return
	if len(parts) == 2 {
		p.end = parse_grid_line(parts[1]) or_return
	} else if p.start.kind == .Name {
		p.end = p.start // a name alone: the whole area on this axis
	}
	return p, true
}

// grid-area: a name, or "<row-start> / <column-start> / <row-end> / <column-end>".
@(private)
parse_grid_area_property :: proc(g: ^Grid, value: string) {
	parts := strings.split(value, "/", context.temp_allocator)
	lines: [4]Grid_Line
	if len(parts) > 4 {
		return
	}
	for part, i in parts {
		line, ok := parse_grid_line(part)
		if !ok {
			return
		}
		lines[i] = line
	}
	// missing parts: a name stands for its area on the other sides too
	name_or_auto :: proc(line: Grid_Line) -> Grid_Line {
		return line if line.kind == .Name else {}
	}
	if len(parts) < 2 {
		lines[1] = name_or_auto(lines[0])
	}
	if len(parts) < 3 {
		lines[2] = name_or_auto(lines[0])
	}
	if len(parts) < 4 {
		lines[3] = name_or_auto(lines[1])
	}
	g.row = {lines[0], lines[2]}
	g.column = {lines[1], lines[3]}
}

// One line: auto, a number (negative from the end), "span n" or an area name.
@(private)
parse_grid_line :: proc(value: string) -> (line: Grid_Line, ok: bool) {
	v := strings.to_lower(strings.trim_space(value), context.temp_allocator)
	switch {
	case v == "auto" || v == "initial" || v == "unset":
		return {}, true
	case strings.has_prefix(v, "span"):
		rest := strings.trim_space(v[4:])
		if rest == "" {
			return {kind = .Span, value = 1}, true
		}
		n, is_number := strconv.parse_int(rest)
		if !is_number {
			return {kind = .Span, value = 1}, true // span <name>: one track
		}
		return {kind = .Span, value = max(n, 1)}, true
	}
	if n, is_number := strconv.parse_int(v); is_number {
		if n == 0 {
			return {}, false
		}
		return {kind = .Line, value = n}, true
	}
	if strings.contains_any(v, " ()") {
		return {}, false
	}
	return {kind = .Name, name = v}, true
}

// The slices and names of a grid are in the temp allocator while the style
// is computed; this copies them to the document's.
@(private)
clone_grid :: proc(g: ^Grid, allocator := context.allocator) {
	clone_tracks :: proc(t: []Track, allocator := context.allocator) -> []Track {
		if t == nil {
			return nil
		}
		result := make([]Track, len(t), allocator)
		copy(result, t)
		return result
	}
	g.columns = clone_tracks(g.columns, allocator)
	g.rows = clone_tracks(g.rows, allocator)
	g.auto_repeat.tracks = clone_tracks(g.auto_repeat.tracks, allocator)
	if g.areas != nil {
		areas := make([]Grid_Area, len(g.areas), allocator)
		for area, i in g.areas {
			areas[i] = area
			areas[i].name = strings.clone(area.name, allocator)
		}
		g.areas = areas
	}
	g.column.start.name = strings.clone(g.column.start.name, allocator)
	g.column.end.name = strings.clone(g.column.end.name, allocator)
	g.row.start.name = strings.clone(g.row.start.name, allocator)
	g.row.end.name = strings.clone(g.row.end.name, allocator)
}
