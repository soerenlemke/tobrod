package layout

import "core:fmt"
import "core:mem"
import "core:mem/virtual"
import "core:strconv"
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
	hidden:    bool,   // visibility: hidden - takes up space, but is dropped in finish_line
	clip:      Clip,
	decoration: dom.Decoration, // underline etc., drawn by the ui with the text
	decoration_lead: f32,       // the lines also cover this much space before the run
	line_height: f32,           // of its text (line-height in px); the text sits in the middle
}

// A block box: background (alpha 0 = none) and borders. x/y/width/height is
// the border box (border + padding + content), the background fills all of it.
Box :: struct {
	x, y, width, height: f32,
	color:               dom.Color,
	border:              [dom.Edge]f32, // widths in px, 0 = none
	border_color:        [dom.Edge]dom.Color,
	clip:                Clip,
}

// An <img>: where it goes and how big it is. The ui draws the decoded image
// there, or a placeholder while it is not loaded (yet).
Image_Item :: struct {
	src:                 string, // as written in the page, also the key for Image_Sizes
	x, y, width, height: f32,
	link:                string, // href of the surrounding <a>, "" if none
	hidden:              bool,   // visibility: hidden
	clip:                Clip,
}

// overflow: hidden cuts off what sticks out of a box. Every box, run and
// image of such a box refers to the clip rectangle it must be drawn in:
// 0 = none, otherwise Layout.clips[clip - 1] (in the coordinates of the
// layer the item is in). Nested clips are already intersected.
Clip :: distinct int

Clip_Rect :: struct {
	x, y, width, height: f32,
}

// Natural sizes of the images that are already loaded, by src as written in
// the page. Images not in the map get their size from the page or a placeholder.
Image_Sizes :: map[string][2]f32

// Owns all boxes, runs, images and their strings; destroy frees everything at once.
// Draw order: background, then boxes in order (parents before children), then
// images and runs.
Layout :: struct {
	arena:      virtual.Arena,
	background: dom.Color, // page background from <html> or <body> ("canvas")
	boxes:      [dynamic]Box,
	runs:       [dynamic]Text_Run,
	images:     [dynamic]Image_Item,
	viewport:   [2]f32, // the size this layout was made for (width, height of the page view)
	height:     f32,    // total content height
	fixed:      Fixed_Layer, // position: fixed, drawn last and not scrolled
	clips:      [dynamic]Clip_Rect, // see Clip
}

// The clip rectangle of an item, false if it is not clipped.
clip_rect :: proc(l: ^Layout, clip: Clip) -> (Clip_Rect, bool) {
	if clip == 0 {
		return {}, false
	}
	return l.clips[clip - 1], true
}

// Elements with position: fixed stay where they are when the page scrolls.
// Their coordinates are relative to the top left of the viewport (the page
// view), not the page; the ui draws them after everything else.
Fixed_Layer :: struct {
	boxes:  [dynamic]Box,
	runs:   [dynamic]Text_Run,
	images: [dynamic]Image_Item,
}

PAGE_BACKGROUND :: dom.Color{255, 255, 255, 255}

Measure_Text :: #type proc(text: string, font_size: f32, bold: bool) -> f32

// The content area of text, what an inline background covers: about the
// height of the font's glyphs, independent of line-height.
CONTENT_AREA_FACTOR :: dom.NORMAL_LINE_HEIGHT
IMAGE_PLACEHOLDER_SIZE :: f32(16) // for an image whose size is not known (yet)
// Other replaced elements (video, iframe, canvas, ...) are 300x150 by default,
// like in every browser.
REPLACED_DEFAULT_SIZE :: [2]f32{300, 150}
BOLD_WEIGHT :: 600              // from this font-weight on we draw bold

// viewport is the visible page area: its width is the page width, both
// together resolve vw/vh.
build :: proc(doc: ^dom.Document, viewport: [2]f32, measure: Measure_Text, image_sizes: Image_Sizes = nil) -> ^Layout {
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
	l.images.allocator = allocator
	l.clips.allocator = allocator
	l.background = PAGE_BACKGROUND

	// the page margin is no special case anymore: it is the default margin of body
	b := Builder {
		layout    = l,
		allocator = allocator,
		measure   = measure,
		left      = 0,
		right     = width,
		viewport  = viewport,
		image_sizes = image_sizes,
	}
	b.line.allocator = allocator
	b.line_images.allocator = allocator
	b.floats.allocator = allocator
	b.block_tops.allocator = allocator
	b.positioned.allocator = allocator
	b.containing.allocator = allocator
	b.fixed_waiting.allocator = allocator
	b.inline_fragments.allocator = allocator
	b.line_blocks.allocator = allocator

	// the initial containing block: absolute elements without a positioned
	// ancestor are placed against the first screen of the page
	begin_containing_block(&b)
	layout_node(&b, doc.root)
	finish_line(&b)
	b.last_box = {width = viewport.x, height = viewport.y, index = -1}
	end_containing_block(&b)
	draw_positioned_last(&b)
	l.height = max(b.y + b.pending_margin, b.overflow)
	place_fixed(&b) // they don't make the page taller
	for f in b.floats {
		l.height = max(l.height, f.y + f.height) // the page grows with its floats
	}
	return l
}

destroy :: proc(l: ^Layout) {
	virtual.arena_destroy(&l.arena)
	free(l)
}

// The link under a point of the page (layout coordinates), "" if there is none.
// The whole line box of a run counts, so clicks between the lines still hit.
// Fixed elements are on top: they are checked first, in viewport coordinates
// (scroll_y is how far the page is scrolled).
link_at :: proc(l: ^Layout, x, y: f32, scroll_y: f32 = 0) -> (link: string, ok: bool) {
	if link, ok = link_in(l, l.fixed.runs[:], l.fixed.images[:], x, y - scroll_y); ok {
		return
	}
	return link_in(l, l.runs[:], l.images[:], x, y)
}

@(private)
link_in :: proc(l: ^Layout, runs: []Text_Run, images: []Image_Item, x, y: f32) -> (link: string, ok: bool) {
	// a clipped part of a link is not there
	visible :: proc(l: ^Layout, clip: Clip, x, y: f32) -> bool {
		r, clipped := clip_rect(l, clip)
		return !clipped || x >= r.x && x <= r.x + r.width && y >= r.y && y <= r.y + r.height
	}
	for image in images {
		if image.link != "" && x >= image.x && x <= image.x + image.width && y >= image.y && y <= image.y + image.height && visible(l, image.clip, x, y) {
			return image.link, true
		}
	}
	for run in runs {
		if run.link == "" {
			continue
		}
		top := run.y - (run.line_height - run.font_size) / 2
		if x >= run.x && x <= run.x + run.width && y >= top && y <= top + run.line_height && visible(l, run.clip, x, y) {
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
	line_images:    [dynamic]Image_Item, // images of the current line, y is set in finish_line
	pending_marker: Maybe(Pending_Marker), // list marker waiting for the first line of its li
	image_sizes:    Image_Sizes,
	extent:         f32, // rightmost edge of text and images so far (for measuring, see table.odin)
	measuring:      bool, // a trial layout to measure content width: no text-align
	line_left:      f32,  // the space of the current line: between the floats (see float.odin)
	line_right:     f32,
	floats:         [dynamic]Float_Box, // of the current block formatting context
	last_float_top: f32,  // a float is never placed above an earlier one
	unfloat:        ^dom.Node, // the float whose own box is being laid out right now
	offset:         [2]f32, // of the open position: relative inline elements, see layout_element
	positioned:     [dynamic][2]int, // box ranges [first, end) of positioned elements, drawn last
	containing:     [dynamic]Containing_Block, // open positioned elements, see position.odin
	fixed_waiting:  [dynamic]Waiting_Absolute, // position: fixed, placed at the end
	inline_fragments: [dynamic]Inline_Fragment, // decorated inline elements on the current line, see inline.odin
	pending_inline_left: f32, // room the left side of inline elements wants before the next word
	marker_run:     int,  // index + 1 of the list marker in b.line, 0 = none
	line_blocks:    [dynamic]Inline_Block_Item, // inline blocks of the current line, see inline_block.odin
	last_box:       Placed_Box, // border box of the block (or table, flex container) laid out last
	overflow:       f32,  // bottom of absolute elements: the page grows with them
}

// The top edge of an open block. It is only known once the collapsed margin
// above it is applied (the top margin of the block may still collapse with
// the one of its first child), so it stays unresolved until then.
// A list marker belongs to the first line of its list item, which may be deep
// inside nested blocks (<li><div><a>...). So it waits until a line starts.
@(private)
Pending_Marker :: struct {
	text:  string,
	right: f32, // the content edge of the li: the marker hangs left of it
	style: dom.Style,
	scale: f32, // of the font size (the triangles of <summary> are big glyphs)
}

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
		if dom.hidden_by_details(node) {
			return
		}
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
	// out of the normal flow: absolute elements are placed when their
	// containing block is done, fixed ones at the very end (position.odin).
	// b.unfloat is the element being laid out as its own root.
	if style.position == .Absolute && node != b.unfloat {
		register_absolute(b, node)
		return
	}
	if style.position == .Fixed && node != b.unfloat {
		register_fixed(b, node)
		return
	}
	if style.float != .None && node != b.unfloat {
		layout_float(b, node)
		return
	}
	if node.tag == "br" {
		line_break(b, style)
		return
	}
	// placed in the line as a whole; inside, laid out as its own root below
	if (style.display == .Inline_Block || style.display == .Inline_Flex) && node != b.unfloat && !is_replaced_element(node.tag) {
		layout_inline_block(b, node)
		return
	}

	// position: relative moves the element after the layout, without changing
	// the place of anything else. Blocks are moved as a whole when they are
	// done; inline content is still waiting in the current line, so its runs
	// and images remember the offset until finish_line places them.
	// (defer is per block in Odin, so these are at proc level.)
	offset := relative_offset(b, style)
	moves_as_block := style.position == .Relative && (style.display != .Inline || style.float != .None) && !is_replaced_element(node.tag)
	// overflow: hidden cuts off the content when the element is done: after a
	// relative shift (this defer runs after the one below)
	clips_x, clips_y := clips_overflow(style)
	clips := (clips_x || clips_y) && !b.measuring && style.display != .Inline && !is_replaced_element(node.tag)
	if (moves_as_block || clips) && style.float == .None {
		finish_line(b) // the lines before belong to the parent
	}
	clipped := display_range_start(b)
	defer if clips {
		clipped = display_range_end(b, clipped)
		clip_contents(b, clipped, clips_x, clips_y, offset if moves_as_block else {})
	}
	moved := display_range_start(b)
	defer if moves_as_block {
		moved = display_range_end(b, moved)
		shift_items(b, moved, offset.y, offset.x)
		add_positioned(b, moved.first_box, moved.end_box)
	}
	inline_offset := offset if !moves_as_block else {}
	if style.display == .Inline && node.parent != nil {
		inline_offset.y += baseline_shift(style.vertical_align, node.parent.style.font_size)
	}
	if inline_offset != {} {
		b.offset += inline_offset
		b.can_extend = false // a run must not continue across the edge
	}
	defer if inline_offset != {} {
		b.offset -= inline_offset
		b.can_extend = false
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

	if is_replaced_element(node.tag) && style.display != .None {
		layout_image(b, node)
		return
	}

	// a positioned element is the containing block of the absolute elements
	// inside it; they are placed when it is done (before a relative shift,
	// which then moves them along)
	out_of_flow := style.position == .Absolute || style.position == .Fixed
	is_container := style.position != .Static && !b.measuring && (style.display != .Inline || out_of_flow)
	if is_container {
		begin_containing_block(b)
	}
	defer if is_container {
		end_containing_block(b)
	}

	if style.display == .Table {
		layout_table(b, node)
		return
	}
	if dom.is_flex_container(style.display) {
		layout_flex(b, node)
		return
	}

	// (table rows and cells outside of a table are laid out like blocks;
	// absolute and fixed elements are blocks, too)
	if style.display == .Inline && !out_of_flow {
		decorated := inline_decorated(style)
		if decorated {
			begin_inline(b, node)
		}
		for child in node.children {
			layout_node(b, child)
		}
		if decorated {
			end_inline(b, node)
		}
		return
	}

	layout_block(b, node)
}

// A block or list item: the CSS box model, simplified (box-sizing is
// always content-box).
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
		padding[edge] = max(dom.resolve_length(style.padding[edge], font_size, available, b.viewport), 0) // calc() can be negative
		border[edge] = dom.border_width_px(style.border[edge], font_size, b.viewport)
		inset[edge] = padding[edge] + border[edge]
	}

	// horizontal: content width first, then auto margins take what is left
	inset_x := inset[.Left] + inset[.Right]
	width, has_width := specified_width(b, style, available, inset_x)
	if !has_width {
		width = available - margin[.Left] - margin[.Right] - inset_x
	}
	width = clamp_width(b, style, available, inset_x, width)

	left_auto := style.margin[.Left].unit == .Auto || centered_by_parent(node)
	right_auto := style.margin[.Right].unit == .Auto || centered_by_parent(node)
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
	if style.clear != .None {
		// below the floats (the margin above is then applied right away)
		if y := clear_y(b, style.clear); y > b.y + b.pending_margin {
			flush_margin(b)
			b.y = y
		}
	}
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
	if (box_background[3] > 0 || has_border) && style.visibility == .Visible {
		append(&b.layout.boxes, Box{})
		box_index = len(b.layout.boxes) - 1
	}

	old_left, old_right, old_align := b.left, b.right, b.text_align
	b.left = box_x + inset[.Left]
	b.right = b.left + width
	b.x = b.left
	b.text_align = style.text_align

	if style.display == .List_Item {
		set_pending_marker(b, node)
	}
	for child in node.children {
		layout_node(b, child)
	}

	finish_line(b)
	if style.display == .List_Item {
		b.pending_marker = nil // an empty list item: no line got the marker
	}
	apply_block_height(b, style, inset[.Top], inset[.Top] + inset[.Bottom], available)
	if inset[.Bottom] > 0 {
		flush_margin(b) // the bottom margin of the last child stays inside
		b.y += inset[.Bottom]
	}

	top := pop(&b.block_tops)
	if !top.resolved {
		top.y = b.y // no content and no padding: an empty box
	}
	b.last_box = {box_x, top.y, box_width, b.y - top.y, border, box_index}
	if box_index >= 0 {
		box := Box{box_x, top.y, box_width, b.y - top.y, box_background, border, {}, 0}
		for edge in dom.Edge {
			box.border_color[edge] = dom.border_color(style.border[edge], style.color)
		}
		b.layout.boxes[box_index] = box
	}

	b.left, b.right, b.text_align = old_left, old_right, old_align
	b.x = b.left
	add_margin(b, margin[.Bottom])
}

// height, min-height and max-height: moves y to the bottom of the content box.
// Content taller than the box overflows (it stays visible, like overflow:
// visible), the next block then starts at the box's bottom.
@(private)
apply_block_height :: proc(b: ^Builder, style: dom.Style, inset_top, inset_y, available: f32) {
	height, has_height := block_height(b, style, style.height, available, inset_y)
	min_height, has_min := block_height(b, style, style.min_height, available, inset_y)
	max_height, has_max := block_height(b, style, style.max_height, available, inset_y)
	has_min = has_min && min_height > 0
	if !has_height && !has_min && !has_max {
		return
	}
	// a box with a height keeps the bottom margin of its last child inside;
	// this also fixes the top of the box if it is still empty
	flush_margin(b)
	content_top := b.block_tops[len(b.block_tops) - 1].y + inset_top
	h := height if has_height else b.y - content_top
	if has_max {
		h = min(h, max_height)
	}
	if has_min {
		h = max(h, min_height) // min-height wins over max-height
	}
	b.y = content_top + max(h, 0)
}

// A height in px, or false for auto. Percentages would refer to the height
// of the containing block, which is usually not known (auto), so they count
// as auto.
@(private)
block_height :: proc(b: ^Builder, style: dom.Style, length: dom.Length, available, inset_y: f32) -> (f32, bool) {
	if length.unit == .Auto || dom.has_percent(length) {
		return 0, false
	}
	return content_size(b, style, length, available, inset_y), true // box-sizing
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
	for word in next_word(&rest) {
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
	if line_empty(b) {
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
	inline_left := b.pending_inline_left // padding etc. of inline elements starting here

	// wrap; a word wider than the line stays alone on its line
	if !line_empty(b) && b.x + space_width + inline_left + width > b.line_right {
		finish_line(b)
		space_width = 0
	}
	if line_empty(b) {
		line_height := dom.line_height_px(style)
		start_line(b, line_height)
		fit_line(b, inline_left + width, line_height) // below a float if it doesn't fit next to it
		space_width = 0
	}
	only_space := space_width // without the padding etc. of inline elements
	space_width += take_inline_left(b)

	// same style as the previous run: extend it instead of starting a new one
	if b.can_extend && len(b.line) > 0 {
		last := &b.line[len(b.line) - 1]
		if b.can_extend && same_style(last^, style) && last.link == b.link && last.hidden == (style.visibility == .Hidden) {
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
		x         = b.x + space_width + b.offset.x,
		y         = b.offset.y, // the line's y is added in finish_line
		width     = width,
		font_size = style.font_size,
		bold      = bold,
		color     = style.color,
		link      = b.link,
		hidden    = style.visibility == .Hidden,
		decoration = style.decoration,
		line_height = dom.line_height_px(style),
		// a space that is itself decorated (inside the same link) is drawn
		// with the line, like "with a" -> "bold" in <a>with a <b>bold</b></a>
		decoration_lead = only_space if b.pending_space && b.space_style.decoration == style.decoration else 0,
	})
	b.x += space_width + width
	b.pending_space = false
	b.can_extend = true
}

// Preserved spaces (in <pre>) only move the cursor; dropped at a wrap.
@(private)
place_spaces :: proc(b: ^Builder, spaces: string, style: dom.Style) {
	if line_empty(b) {
		start_line(b, dom.line_height_px(style))
	}
	b.x += b.measure(spaces, style.font_size, style.font_weight >= BOLD_WEIGHT)
	b.pending_space = false
	b.can_extend = false // the run would lose the exact spacing
}

// The marker of a list item, placed on its first line (see start_line).
@(private)
set_pending_marker :: proc(b: ^Builder, node: ^dom.Node) {
	style := node.style
	marker: string
	scale: f32 = 1
	switch style.list_style {
	case .Disc:
		marker = "•"
	case .Circle:
		marker = "◦"
	case .Square:
		marker = "▪"
	case .Decimal:
		marker = fmt.aprintf("%d.", list_index(node), allocator = b.allocator)
	case .Disclosure_Closed:
		marker = "▶"
		scale = 0.6
	case .Disclosure_Open:
		marker = "▼"
		scale = 0.6
	case .None:
		b.pending_marker = nil
		return
	}
	b.pending_marker = Pending_Marker{marker, b.left, style, scale}
}

// The marker hangs left of the content (list-style-position: outside), or
// with inside it is the first thing in the line.
@(private)
place_marker :: proc(b: ^Builder, marker: Pending_Marker) {
	style := marker.style
	bold := style.font_weight >= BOLD_WEIGHT
	gap := b.measure(" ", style.font_size, bold)
	font_size := style.font_size * marker.scale
	width := b.measure(marker.text, font_size, bold)
	x := marker.right - gap - width
	if style.list_inside {
		x = b.x
		b.x += width + gap
	} else {
		b.marker_run = len(b.line) + 1 // stays where it is with text-align
	}
	append(&b.line, Text_Run {
		text      = marker.text,
		x         = x,
		width     = width,
		// a smaller marker (the triangle of <summary>) doesn't make the line
		// higher, and is centered on the text instead of sitting on the baseline
		y           = -(style.font_size - font_size) / 2,
		line_height = dom.line_height_px(style) - style.font_size + font_size,
		font_size = font_size,
		bold      = bold,
		color     = style.color,
		hidden    = style.visibility == .Hidden,
	})
}

// A <br> or a newline in <pre>: ends the line; on an empty line it adds an empty one.
@(private)
line_break :: proc(b: ^Builder, style: dom.Style) {
	if line_empty(b) {
		start_line(b, dom.line_height_px(style))
		b.y += dom.line_height_px(style)
		b.x = b.left
		return
	}
	finish_line(b)
}

// First content on a line: the collapsed margin above becomes real space now,
// and the line gets the space next to the floats at its height.
@(private)
start_line :: proc(b: ^Builder, height: f32) {
	if !line_empty(b) {
		return
	}
	flush_margin(b)
	b.line_left, b.line_right = line_bounds(b, b.y, height)
	b.x = b.line_left
	b.can_extend = false
	if marker, ok := b.pending_marker.?; ok {
		b.pending_marker = nil
		place_marker(b, marker)
	}
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
	if line_empty(b) {
		return
	}
	// as high as the largest font or image on it; text and images sit on the
	// bottom of that, the "baseline" of the line. Inline blocks can hang
	// below it (their padding and border under their last line of text).
	block_above, below := line_block_extent(b)
	line_height := block_above
	for run in b.line {
		line_height = max(line_height, run.line_height)
	}
	for image in b.line_images {
		line_height = max(line_height, image.height)
	}

	// text-align: move the line by the free space (or half of it). List markers
	// hang left of b.left and stay where they are.
	// (not while measuring: centering in an "infinitely" wide trial layout
	// would move the content far to the right and make it look huge)
	align_shift: f32 = 0
	if b.text_align != .Left && !b.measuring {
		line_end := b.line_left
		for run in b.line {
			if run.x >= b.left {
				line_end = max(line_end, run.x + run.width)
			}
		}
		for image in b.line_images {
			line_end = max(line_end, image.x + image.width)
		}
		for item in b.line_blocks {
			line_end = max(line_end, item.x + item.width)
		}
		shift := max(b.line_right - line_end, 0)
		if b.text_align == .Center || b.text_align == .Legacy_Center {
			shift /= 2
		}
		for &run in b.line {
			if run.x >= b.left {
				run.x += shift
			}
		}
		for &image in b.line_images {
			image.x += shift
		}
		align_shift = shift
	}

	for &run in b.line {
		// bottom-align smaller text, centered in its own line box
		own_height := run.line_height
		run.y += b.y + (line_height - own_height) + (own_height - run.font_size) / 2
		b.extent = max(b.extent, run.x + run.width)
		if !run.hidden {
			append(&b.layout.runs, run)
		}
	}
	// images sit on the bottom of the line, like text
	for &image in b.line_images {
		image.y += b.y + line_height - image.height
		b.extent = max(b.extent, image.x + image.width)
		if !image.hidden {
			append(&b.layout.images, image)
		}
	}
	place_inline_boxes(b, b.y, line_height)
	place_line_blocks(b, align_shift, b.y + line_height)
	clear(&b.line)
	clear(&b.line_images)
	b.marker_run = 0
	b.y += line_height + below
	b.x = b.left
	b.pending_space = false
}

@(private)
line_empty :: proc(b: ^Builder) -> bool {
	return len(b.line) == 0 && len(b.line_images) == 0 && len(b.line_blocks) == 0
}

// An image is an inline box with a fixed size: it is placed in the line like
// a (big) word, wraps like one, and makes the line as high as itself.
@(private)
layout_image :: proc(b: ^Builder, node: ^dom.Node) {
	src := image_source(node)
	width, height := image_size(b, node, src)

	space_width: f32 = 0
	if b.pending_space {
		space_width = b.measure(" ", b.space_style.font_size, b.space_style.font_weight >= BOLD_WEIGHT)
	}
	inline_left := b.pending_inline_left
	if !line_empty(b) && b.x + space_width + inline_left + width > b.line_right {
		finish_line(b)
		space_width = 0
	}
	if line_empty(b) {
		start_line(b, height)
		fit_line(b, inline_left + width, height)
		space_width = 0
	}
	space_width += take_inline_left(b)

	append(&b.line_images, Image_Item {
		src    = strings.clone(src, b.allocator),
		x      = b.x + space_width + b.offset.x,
		y      = b.offset.y, // the line's y is added in finish_line
		width  = width,
		height = height,
		link   = b.link,
		hidden = node.style.visibility == .Hidden,
	})
	b.x += space_width + width
	b.pending_space = false
	b.can_extend = false // text after the image starts a new run
}

// The size of an image, like a browser picks it:
// 1. CSS width/height, 2. the width/height attributes, 3. the natural size of
// the loaded image. If only one side is given, the other keeps the aspect
// ratio of the image. Unknown sides get the placeholder size. max-width
// shrinks the image, keeping its proportions (often max-width: 100%).
@(private)
image_size :: proc(b: ^Builder, node: ^dom.Node, src: string) -> (width, height: f32) {
	style := node.style
	available := b.right - b.left

	w, h: Maybe(f32)
	if style.width.unit != .Auto {
		w = dom.resolve_length(style.width, style.font_size, available, b.viewport)
	} else if v, ok := attribute_px(node, "width"); ok {
		w = v
	}
	// percentages of a height would need the height of the containing block
	if style.height.unit != .Auto && !dom.has_percent(style.height) {
		h = dom.resolve_length(style.height, style.font_size, available, b.viewport)
	} else if v, ok := attribute_px(node, "height"); ok {
		h = v
	}

	natural, loaded := b.image_sizes[src]
	if loaded && natural.x > 0 && natural.y > 0 {
		ratio := natural.y / natural.x
		switch {
		case w == nil && h == nil:
			w, h = natural.x, natural.y
		case h == nil:
			h = w.? * ratio
		case w == nil:
			w = h.? / ratio
		}
	}
	placeholder := [2]f32{IMAGE_PLACEHOLDER_SIZE, IMAGE_PLACEHOLDER_SIZE} if node.tag == "img" else REPLACED_DEFAULT_SIZE
	width = w.? or_else placeholder.x
	height = h.? or_else placeholder.y

	if style.max_width.unit != .Auto {
		max_width := dom.resolve_length(style.max_width, style.font_size, available, b.viewport)
		if width > max_width && width > 0 {
			height *= max_width / width
			width = max_width
		}
	}
	return max(width, 0), max(height, 0)
}

// "Replaced elements": their content comes from outside the page (an image, a
// video, another page...), the layout only reserves a rectangle for them.
is_replaced_element :: proc(tag: string) -> bool {
	switch tag {
	case "img", "video", "iframe", "canvas", "embed", "object":
		return true
	}
	return false
}

// The picture to show for a replaced element: the image of <img>, the
// preview of a <video> ("poster"); others get a placeholder. Also the key for
// Image_Sizes.
image_source :: proc(node: ^dom.Node) -> string {
	switch node.tag {
	case "img":
		src, _ := dom.attribute(node, "src")
		return src
	case "video":
		poster, _ := dom.attribute(node, "poster")
		return poster
	}
	return ""
}

// width="200" -> 200. Percentages and junk are ignored.
@(private)
attribute_px :: proc(node: ^dom.Node, name: string) -> (value: f32, ok: bool) {
	text := dom.attribute(node, name) or_return
	text = strings.trim_suffix(strings.trim_space(text), "px")
	value = strconv.parse_f32(text) or_return
	return value, value >= 0
}

// Adjacent vertical margins collapse: the larger one wins instead of adding up.
@(private)
add_margin :: proc(b: ^Builder, margin: f32) {
	b.pending_margin = max(b.pending_margin, margin)
}

@(private)
same_style :: proc(run: Text_Run, style: dom.Style) -> bool {
	return run.font_size == style.font_size && run.bold == (style.font_weight >= BOLD_WEIGHT) && run.color == style.color &&
		run.decoration == style.decoration
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

// The next word of text, split at white space as CSS sees it: unlike
// strings.fields, not at a no-break space (U+00A0), which stays in the word.
@(private)
next_word :: proc(rest: ^string) -> (word: string, ok: bool) {
	start := 0
	for start < len(rest) && is_space(rest[start]) {
		start += 1
	}
	if start == len(rest) {
		rest^ = ""
		return "", false
	}
	end := start
	for end < len(rest) && !is_space(rest[end]) {
		end += 1
	}
	word = rest[start:end]
	rest^ = rest[end:]
	return word, true
}

// <center> (or align="center") around a block centers it, as if its side
// margins were auto - unless they are set.
@(private)
centered_by_parent :: proc(node: ^dom.Node) -> bool {
	if node.parent == nil || node.parent.style.text_align != .Legacy_Center {
		return false
	}
	margin := node.style.margin
	return dom.is_zero(margin[.Left]) && dom.is_zero(margin[.Right])
}

// vertical-align: super and sub move an inline element up or down, by a part
// of the parent's font size (like browsers do). The line doesn't get higher.
@(private)
baseline_shift :: proc(align: dom.Vertical_Align, parent_font_size: f32) -> f32 {
	#partial switch align {
	case .Super:
		return -parent_font_size / 3
	case .Sub:
		return parent_font_size / 5
	}
	return 0
}
