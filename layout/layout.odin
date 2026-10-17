package layout

import "core:fmt"
import "core:mem"
import "core:mem/virtual"
import "core:strings"
import "../dom"

// Turns a styled DOM into a "display list" of background boxes and positioned
// pieces of text, which the ui just has to draw. Simplified block and inline layout:
// - block elements stack vertically: CSS box model with margin, padding, width,
//   max-width, auto margins (centering) and collapsing vertical margins
// - inline text is split into words and wrapped into lines
// - a line is as high as its largest font, smaller text sits at the bottom
// layout knows nothing about fonts: text width comes from a Measure_Text proc,
// the ui passes one that asks raylib, the tests a fake one.

// One piece of text with a single style, x/y is its top left corner.
Text_Run :: struct {
	text:      string,
	x, y:      f32,
	width:     f32,
	font_size: f32,
	bold:      bool,
	color:     dom.Color,
	link:      string, // href of the surrounding <a>, as written in the page; "" if none
}

// A block box: background (alpha 0 = none) and borders. x/y/width/height is
// the border box (border + padding + content), the background fills all of it.
Box :: struct {
	x, y, width, height: f32,
	color:               dom.Color,
	border:              [dom.Edge]f32, // widths in px, 0 = none
	border_color:        [dom.Edge]dom.Color,
}

// Owns all boxes, runs and their strings; destroy frees everything at once.
// Draw order: background, then boxes in order (parents before children), then runs.
Layout :: struct {
	arena:      virtual.Arena,
	background: dom.Color, // page background from <html> or <body> ("canvas")
	boxes:      [dynamic]Box,
	runs:       [dynamic]Text_Run,
	viewport:   [2]f32, // the size this layout was made for (width, height of the page view)
	height:     f32,    // total content height
}

PAGE_BACKGROUND :: dom.Color{255, 255, 255, 255}

Measure_Text :: #type proc(text: string, font_size: f32, bold: bool) -> f32

LINE_HEIGHT_FACTOR :: f32(1.25) // line height relative to the font size ("normal")
BOLD_WEIGHT :: 600              // from this font-weight on we draw bold

// viewport is the visible page area: its width is the page width, both
// together resolve vw/vh.
build :: proc(doc: ^dom.Document, viewport: [2]f32, measure: Measure_Text) -> ^Layout {
	l := new(Layout)
	l.viewport = viewport
	width := viewport.x
	if err := virtual.arena_init_growing(&l.arena); err != nil {
		// out of memory: an empty layout is the best we can do
		return l
	}
	allocator := virtual.arena_allocator(&l.arena)
	l.runs.allocator = allocator
	l.boxes.allocator = allocator
	l.background = PAGE_BACKGROUND

	// the page margin is no special case anymore: it is the default margin of body
	b := Builder {
		layout    = l,
		allocator = allocator,
		measure   = measure,
		left      = 0,
		right     = width,
		viewport  = viewport,
	}
	b.line.allocator = allocator
	b.block_tops.allocator = allocator

	layout_node(&b, doc.root)
	finish_line(&b)
	l.height = b.y + b.pending_margin
	return l
}

destroy :: proc(l: ^Layout) {
	virtual.arena_destroy(&l.arena)
	free(l)
}

// The link under a point of the page (layout coordinates), "" if there is none.
// The whole line box of a run counts, so clicks between the lines still hit.
link_at :: proc(l: ^Layout, x, y: f32) -> (link: string, ok: bool) {
	for run in l.runs {
		if run.link == "" {
			continue
		}
		line_height := run.font_size * LINE_HEIGHT_FACTOR
		top := run.y - (line_height - run.font_size) / 2
		if x >= run.x && x <= run.x + run.width && y >= top && y <= top + line_height {
			return run.link, true
		}
	}
	return "", false
}

@(private)
Builder :: struct {
	layout:         ^Layout,
	allocator:      mem.Allocator,
	measure:        Measure_Text,
	left, right:    f32,                 // horizontal space of the current block
	y:              f32,                 // top of the current line
	x:              f32,                 // where the next word goes
	line:           [dynamic]Text_Run,   // runs of the current line, y is set in finish_line
	pending_space:  bool,                // a collapsed space waiting for the next word
	space_style:    dom.Style,           // style of that space (for its width)
	pending_margin: f32,                 // collapsed vertical margin before the next line
	can_extend:     bool,                // the next word may be appended to the last run
	link:           string,              // href of the <a> we are in, "" outside of links
	block_tops:     [dynamic]Block_Top,  // one per open block, see flush_margin
	canvas_from_html: bool,              // <html> set the page background, <body> must not override it
	viewport:       [2]f32,
	text_align:     dom.Text_Align,      // of the block the current line belongs to
}

// The top edge of an open block. It is only known once the collapsed margin
// above it is applied (the top margin of the block may still collapse with
// the one of its first child), so it stays unresolved until then.
@(private)
Block_Top :: struct {
	y:        f32,
	resolved: bool,
}

@(private)
layout_node :: proc(b: ^Builder, node: ^dom.Node) {
	switch node.kind {
	case .Document:
		for child in node.children {
			layout_node(b, child)
		}
	case .Comment:
	case .Text:
		style := node.parent.style
		if in_pre(node) {
			layout_pre_text(b, node.text, style)
		} else {
			layout_text(b, node.text, style)
		}
	case .Element:
		layout_element(b, node)
	}
}

@(private)
layout_element :: proc(b: ^Builder, node: ^dom.Node) {
	style := node.style
	if style.display == .None {
		return
	}
	if node.tag == "br" {
		line_break(b, style)
		return
	}

	// Everything inside an <a href> belongs to that link (the innermost one wins).
	// Note: defer is scoped to the block in Odin, so it must be at proc level here,
	// inside the if it would restore the link right away.
	outer_link := b.link
	defer b.link = outer_link
	if node.tag == "a" {
		if href, ok := dom.attribute(node, "href"); ok {
			b.link = strings.clone(href, b.allocator)
		}
	}

	if style.display == .Inline {
		for child in node.children {
			layout_node(b, child)
		}
		return
	}

	layout_block(b, node)
}

// A block or list item: the CSS box model, simplified (no height,
// box-sizing is always content-box).
@(private)
layout_block :: proc(b: ^Builder, node: ^dom.Node) {
	finish_line(b)
	style := node.style
	font_size := style.font_size
	available := b.right - b.left // width of the containing block

	// all percentages (even vertical ones) refer to the width of the containing block
	// padding and border both sit between the margin and the content; for the
	// width calculation and margin collapsing they behave the same, so "inset"
	// is their sum
	margin, padding, border, inset: [dom.Edge]f32
	for edge in dom.Edge {
		margin[edge] = dom.resolve_length(style.margin[edge], font_size, available, b.viewport)
		padding[edge] = dom.resolve_length(style.padding[edge], font_size, available, b.viewport)
		border[edge] = dom.border_width_px(style.border[edge], font_size, b.viewport)
		inset[edge] = padding[edge] + border[edge]
	}

	// horizontal: content width first, then auto margins take what is left
	width: f32
	if style.width.unit == .Auto {
		width = available - margin[.Left] - margin[.Right] - inset[.Left] - inset[.Right]
	} else {
		width = dom.resolve_length(style.width, font_size, available, b.viewport)
	}
	if style.max_width.unit != .Auto {
		width = min(width, dom.resolve_length(style.max_width, font_size, available, b.viewport))
	}
	width = max(width, 0)

	left_auto := style.margin[.Left].unit == .Auto
	right_auto := style.margin[.Right].unit == .Auto
	free := available - width - inset[.Left] - inset[.Right] - margin[.Left] - margin[.Right]
	if free > 0 {
		if left_auto && right_auto {
			margin[.Left] += free / 2 // margin: 0 auto -> centered
		} else if left_auto {
			margin[.Left] += free // pushed to the right
		}
	}
	box_x := b.left + margin[.Left]
	box_width := inset[.Left] + width + inset[.Right]

	// vertical: the top margin joins the pending (collapsing) margin. Padding or
	// a border separates this block from its children, so then the margin is
	// applied now.
	add_margin(b, margin[.Top])
	append(&b.block_tops, Block_Top{})
	if inset[.Top] > 0 {
		flush_margin(b)
		b.y += inset[.Top]
	}

	// html and body paint their background on the whole page ("canvas")
	box_background := style.background
	if box_background[3] > 0 && (node.tag == "html" || node.tag == "body") {
		if node.tag == "html" || !b.canvas_from_html {
			b.layout.background = box_background
		}
		b.canvas_from_html ||= node.tag == "html"
		box_background = {}
	}

	// reserve the box slot now: parents are drawn before their children
	has_border := border[.Top] > 0 || border[.Right] > 0 || border[.Bottom] > 0 || border[.Left] > 0
	box_index := -1
	if box_background[3] > 0 || has_border {
		append(&b.layout.boxes, Box{})
		box_index = len(b.layout.boxes) - 1
	}

	old_left, old_right, old_align := b.left, b.right, b.text_align
	b.left = box_x + inset[.Left]
	b.right = b.left + width
	b.x = b.left
	b.text_align = style.text_align

	if style.display == .List_Item {
		add_marker(b, node)
	}
	for child in node.children {
		layout_node(b, child)
	}

	finish_line(b)
	if inset[.Bottom] > 0 {
		flush_margin(b) // the bottom margin of the last child stays inside
		b.y += inset[.Bottom]
	}

	top := pop(&b.block_tops)
	if !top.resolved {
		top.y = b.y // no content and no padding: an empty box
	}
	if box_index >= 0 {
		box := Box{box_x, top.y, box_width, b.y - top.y, box_background, border, {}}
		for edge in dom.Edge {
			box.border_color[edge] = dom.border_color(style.border[edge], style.color)
		}
		b.layout.boxes[box_index] = box
	}

	b.left, b.right, b.text_align = old_left, old_right, old_align
	b.x = b.left
	add_margin(b, margin[.Bottom])
}

// Normal text: whitespace collapses to single spaces, lines wrap at spaces.
@(private)
layout_text :: proc(b: ^Builder, text: string, style: dom.Style) {
	if len(text) == 0 {
		return
	}
	if is_space(text[0]) {
		request_space(b, style)
	}
	rest := text
	first := true
	for word in strings.fields_iterator(&rest) {
		if !first {
			request_space(b, style)
		}
		place_word(b, word, style)
		first = false
	}
	if !first && is_space(text[len(text) - 1]) {
		request_space(b, style)
	}
}

// Text inside <pre>: spaces and line breaks are kept. Long lines still wrap
// (like white-space: pre-wrap), so plain text documents stay readable.
@(private)
layout_pre_text :: proc(b: ^Builder, text: string, style: dom.Style) {
	rest := text
	first_line := true
	for line in strings.split_iterator(&rest, "\n") {
		if !first_line {
			line_break(b, style)
		}
		first_line = false

		i := 0
		for i < len(line) {
			start := i
			if line[i] == ' ' || line[i] == '\t' {
				for i < len(line) && (line[i] == ' ' || line[i] == '\t') {
					i += 1
				}
				spaces, _ := strings.replace_all(line[start:i], "\t", "    ", context.temp_allocator)
				place_spaces(b, spaces, style)
			} else {
				for i < len(line) && line[i] != ' ' && line[i] != '\t' {
					i += 1
				}
				place_word(b, strings.trim_right(line[start:i], "\r"), style)
			}
		}
	}
}

@(private)
request_space :: proc(b: ^Builder, style: dom.Style) {
	// no space at the start of a line
	if len(b.line) == 0 {
		return
	}
	b.pending_space = true
	b.space_style = style
}

// Places a word on the current line, wrapping first if it doesn't fit.
@(private)
place_word :: proc(b: ^Builder, word: string, style: dom.Style) {
	if len(word) == 0 {
		return
	}
	bold := style.font_weight >= BOLD_WEIGHT
	width := b.measure(word, style.font_size, bold)

	space_width: f32 = 0
	if b.pending_space {
		space_width = b.measure(" ", b.space_style.font_size, b.space_style.font_weight >= BOLD_WEIGHT)
	}

	// wrap; a word wider than the line stays alone on its line
	if len(b.line) > 0 && b.x + space_width + width > b.right {
		finish_line(b)
		space_width = 0
	}
	if len(b.line) == 0 {
		start_line(b)
		space_width = 0
	}

	// same style as the previous run: extend it instead of starting a new one
	if len(b.line) > 0 {
		last := &b.line[len(b.line) - 1]
		if b.can_extend && same_style(last^, style) && last.link == b.link {
			separator := " " if space_width > 0 else ""
			last.text = strings.concatenate({last.text, separator, word}, b.allocator)
			b.x += space_width + width
			last.width = b.x - last.x
			b.pending_space = false
			return
		}
	}

	append(&b.line, Text_Run {
		text      = strings.clone(word, b.allocator),
		x         = b.x + space_width,
		width     = width,
		font_size = style.font_size,
		bold      = bold,
		color     = style.color,
		link      = b.link,
	})
	b.x += space_width + width
	b.pending_space = false
	b.can_extend = true
}

// Preserved spaces (in <pre>) only move the cursor; dropped at a wrap.
@(private)
place_spaces :: proc(b: ^Builder, spaces: string, style: dom.Style) {
	if len(b.line) == 0 {
		start_line(b)
	}
	b.x += b.measure(spaces, style.font_size, style.font_weight >= BOLD_WEIGHT)
	b.pending_space = false
	b.can_extend = false // the run would lose the exact spacing
}

// The list marker hangs left of the text, like list-style-position: outside.
@(private)
add_marker :: proc(b: ^Builder, node: ^dom.Node) {
	marker := "•"
	if node.parent != nil && node.parent.tag == "ol" {
		marker = fmt.tprintf("%d.", list_index(node))
	}
	style := node.style
	bold := style.font_weight >= BOLD_WEIGHT
	gap := b.measure(" ", style.font_size, bold)
	width := b.measure(marker, style.font_size, bold)

	start_line(b)
	append(&b.line, Text_Run {
		text      = strings.clone(marker, b.allocator),
		x         = b.left - gap - width,
		width     = width,
		font_size = style.font_size,
		bold      = bold,
		color     = style.color,
	})
	b.can_extend = false // the marker is positioned on its own
}

// A <br> or a newline in <pre>: ends the line; on an empty line it adds an empty one.
@(private)
line_break :: proc(b: ^Builder, style: dom.Style) {
	if len(b.line) == 0 {
		start_line(b)
		b.y += style.font_size * LINE_HEIGHT_FACTOR
		b.x = b.left
		return
	}
	finish_line(b)
}

// First content on a line: the collapsed margin above becomes real space now.
@(private)
start_line :: proc(b: ^Builder) {
	if len(b.line) > 0 {
		return
	}
	flush_margin(b)
	b.x = b.left
	b.can_extend = false
}

// Applies the collapsed margin. Now the top edges of all blocks that were
// still waiting for it are known: they all start here.
@(private)
flush_margin :: proc(b: ^Builder) {
	b.y += b.pending_margin
	b.pending_margin = 0
	#reverse for &top in b.block_tops {
		if top.resolved {
			break // everything further out was resolved before
		}
		top = {b.y, true}
	}
}

// Fixes the vertical position of all runs of the line and moves y down.
@(private)
finish_line :: proc(b: ^Builder) {
	if len(b.line) == 0 {
		return
	}
	line_height: f32 = 0
	for run in b.line {
		line_height = max(line_height, run.font_size * LINE_HEIGHT_FACTOR)
	}

	// text-align: move the line by the free space (or half of it). List markers
	// hang left of b.left and stay where they are.
	if b.text_align != .Left {
		line_end := b.left
		for run in b.line {
			if run.x >= b.left {
				line_end = max(line_end, run.x + run.width)
			}
		}
		shift := b.right - line_end
		if b.text_align == .Center {
			shift /= 2
		}
		for &run in b.line {
			if run.x >= b.left {
				run.x += max(shift, 0)
			}
		}
	}

	for &run in b.line {
		// bottom-align smaller text, centered in its own line box
		own_height := run.font_size * LINE_HEIGHT_FACTOR
		run.y = b.y + (line_height - own_height) + (own_height - run.font_size) / 2
		append(&b.layout.runs, run)
	}
	clear(&b.line)
	b.y += line_height
	b.x = b.left
	b.pending_space = false
}

// Adjacent vertical margins collapse: the larger one wins instead of adding up.
@(private)
add_margin :: proc(b: ^Builder, margin: f32) {
	b.pending_margin = max(b.pending_margin, margin)
}

@(private)
same_style :: proc(run: Text_Run, style: dom.Style) -> bool {
	return run.font_size == style.font_size && run.bold == (style.font_weight >= BOLD_WEIGHT) && run.color == style.color
}

@(private)
in_pre :: proc(node: ^dom.Node) -> bool {
	for n := node.parent; n != nil; n = n.parent {
		if n.kind == .Element && n.tag == "pre" {
			return true
		}
	}
	return false
}

// 1-based position of a list item among its <li> siblings.
@(private)
list_index :: proc(node: ^dom.Node) -> int {
	index := 0
	for sibling in node.parent.children {
		if sibling.kind == .Element && sibling.tag == "li" {
			index += 1
		}
		if sibling == node {
			break
		}
	}
	return index
}

@(private)
is_space :: proc(c: u8) -> bool {
	return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f'
}
