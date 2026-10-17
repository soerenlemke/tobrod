package layout

import "core:fmt"
import "core:mem"
import "core:mem/virtual"
import "core:strings"
import "../dom"

// Turns a styled DOM into positioned pieces of text (a "display list"), which
// the ui just has to draw. Simplified block and inline layout:
// - block elements stack vertically with collapsing margins
// - inline text is split into words and wrapped into lines
// - a line is as high as its largest font, smaller text sits at the bottom
// layout knows nothing about fonts: text width comes from a Measure_Text proc,
// the ui passes one that asks raylib, the tests a fake one.

// One piece of text with a single style, x/y is its top left corner.
Text_Run :: struct {
	text:      string,
	x, y:      f32,
	font_size: f32,
	bold:      bool,
	color:     dom.Color,
}

// Owns all runs and their strings; destroy frees everything at once.
Layout :: struct {
	arena:  virtual.Arena,
	runs:   [dynamic]Text_Run,
	width:  f32, // the width this layout was made for
	height: f32, // total content height
}

Measure_Text :: #type proc(text: string, font_size: f32, bold: bool) -> f32

LINE_HEIGHT_FACTOR :: f32(1.25) // line height relative to the font size ("normal")
PAGE_MARGIN :: f32(8)           // the default margin of <body>
LIST_INDENT :: f32(40)          // the default padding-left of <ul>/<ol>
BOLD_WEIGHT :: 600              // from this font-weight on we draw bold

build :: proc(doc: ^dom.Document, width: f32, measure: Measure_Text) -> ^Layout {
	l := new(Layout)
	l.width = width
	if err := virtual.arena_init_growing(&l.arena); err != nil {
		// out of memory: an empty layout is the best we can do
		return l
	}
	allocator := virtual.arena_allocator(&l.arena)
	l.runs.allocator = allocator

	b := Builder {
		layout         = l,
		allocator      = allocator,
		measure        = measure,
		left           = PAGE_MARGIN,
		right          = max(width - PAGE_MARGIN, PAGE_MARGIN + 1),
		x              = PAGE_MARGIN,
		pending_margin = PAGE_MARGIN,
	}
	b.line.allocator = allocator

	layout_node(&b, doc.root)
	finish_line(&b)
	l.height = b.y + max(b.pending_margin, PAGE_MARGIN)
	return l
}

destroy :: proc(l: ^Layout) {
	virtual.arena_destroy(&l.arena)
	free(l)
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
	if style.display == .Inline {
		for child in node.children {
			layout_node(b, child)
		}
		return
	}

	// block or list item: starts on a new line, with margins around it
	finish_line(b)
	margin := vertical_margin(node.tag, style.font_size)
	add_margin(b, margin)

	old_left := b.left
	b.left += indent(node.tag)
	b.x = b.left

	if style.display == .List_Item {
		add_marker(b, node)
	}
	for child in node.children {
		layout_node(b, child)
	}

	finish_line(b)
	b.left = old_left
	b.x = b.left
	add_margin(b, margin)
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
		if b.can_extend && same_style(last^, style) {
			separator := " " if space_width > 0 else ""
			last.text = strings.concatenate({last.text, separator, word}, b.allocator)
			b.x += space_width + width
			b.pending_space = false
			return
		}
	}

	append(&b.line, Text_Run {
		text      = strings.clone(word, b.allocator),
		x         = b.x + space_width,
		font_size = style.font_size,
		bold      = bold,
		color     = style.color,
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
	b.y += b.pending_margin
	b.pending_margin = 0
	b.x = b.left
	b.can_extend = false
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

// Default vertical margins from the user agent stylesheet, in em of the element.
@(private)
vertical_margin :: proc(tag: string, font_size: f32) -> f32 {
	switch tag {
	case "p", "ul", "ol", "dl", "pre", "blockquote", "figure", "h3":
		return font_size
	case "h1":
		return font_size * 0.67
	case "h2":
		return font_size * 0.83
	case "h4":
		return font_size * 1.33
	case "h5":
		return font_size * 1.67
	case "h6":
		return font_size * 2.33
	case "hr":
		return font_size * 0.5
	}
	return 0
}

@(private)
indent :: proc(tag: string) -> f32 {
	switch tag {
	case "ul", "ol", "blockquote", "dd":
		return LIST_INDENT
	}
	return 0
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
