package dom

import "core:strings"

// Turns the tree into plain text for display. Not real layout yet, but it
// follows the basic browser rules:
// - invisible elements (head, script, style, template) are skipped
// - whitespace in text collapses to single spaces, except inside <pre>
// - block elements start on a new line, some of them with an empty line around
// - <br> is a line break, list items get a bullet
to_display_text :: proc(doc: ^Document, allocator := context.allocator) -> string {
	w := Text_Writer {
		b = strings.builder_make(allocator),
	}
	write_display_text(&w, doc.root, false)
	return strings.to_string(w.b)
}

@(private)
Text_Writer :: struct {
	b:                strings.Builder,
	// Line breaks requested by block elements. They are only written before the
	// next text, so there are no breaks at the start/end and none pile up.
	pending_breaks:   int,
	// A collapsed space waiting for the next word; dropped at line starts.
	pending_space:    bool,
}

@(private)
write_display_text :: proc(w: ^Text_Writer, node: ^Node, in_pre: bool) {
	switch node.kind {
	case .Document:
		for child in node.children {
			write_display_text(w, child, in_pre)
		}
	case .Comment:
	case .Text:
		if in_pre {
			write_text(w, node.text)
		} else {
			write_collapsed(w, node.text)
		}
	case .Element:
		if is_hidden(node.tag) {
			return
		}
		if node.tag == "br" {
			request_breaks(w, 1, force = true)
			return
		}

		breaks := block_breaks(node.tag)
		request_breaks(w, breaks)
		if node.tag == "li" {
			write_text(w, "• ")
		}

		pre := in_pre || node.tag == "pre"
		for child in node.children {
			write_display_text(w, child, pre)
		}
		request_breaks(w, breaks)
	}
}

// Writes text as is, flushing pending breaks/spaces first.
@(private)
write_text :: proc(w: ^Text_Writer, text: string) {
	if len(text) == 0 {
		return
	}
	if w.pending_breaks > 0 {
		if strings.builder_len(w.b) > 0 {
			for _ in 0 ..< w.pending_breaks {
				strings.write_byte(&w.b, '\n')
			}
		}
		w.pending_breaks = 0
		w.pending_space = false
	}
	if w.pending_space {
		strings.write_byte(&w.b, ' ')
		w.pending_space = false
	}
	strings.write_string(&w.b, text)
}

// HTML whitespace collapsing: any run of spaces, tabs and newlines becomes one space.
@(private)
write_collapsed :: proc(w: ^Text_Writer, text: string) {
	starts_with_space := len(text) > 0 && is_space(text[0])
	ends_with_space := len(text) > 0 && is_space(text[len(text) - 1])

	if starts_with_space && !at_line_start(w) {
		w.pending_space = true
	}
	words := strings.fields(text, context.temp_allocator)
	for word, i in words {
		if i > 0 {
			w.pending_space = true
		}
		write_text(w, word)
	}
	if ends_with_space && len(words) > 0 {
		w.pending_space = true
	}
}

// count = 1: new line, count = 2: new line plus empty line.
// Normally breaks merge (max), a forced break (<br>) always adds one.
@(private)
request_breaks :: proc(w: ^Text_Writer, count: int, force := false) {
	if count == 0 {
		return
	}
	if force {
		if strings.builder_len(w.b) == 0 {
			return
		}
		w.pending_breaks += count
	} else {
		w.pending_breaks = max(w.pending_breaks, count)
	}
	w.pending_space = false
}

@(private)
at_line_start :: proc(w: ^Text_Writer) -> bool {
	n := strings.builder_len(w.b)
	return n == 0 || w.pending_breaks > 0 || w.b.buf[n - 1] == '\n'
}

@(private)
is_space :: proc(c: u8) -> bool {
	return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f'
}

@(private)
is_hidden :: proc(tag: string) -> bool {
	switch tag {
	case "head", "script", "style", "template":
		return true
	}
	return false
}

// Number of line breaks around a block element; 0 means inline.
@(private)
block_breaks :: proc(tag: string) -> int {
	switch tag {
	case "p", "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "dl", "pre", "blockquote", "table", "hr", "figure":
		return 2
	case "div", "li", "dt", "dd", "tr", "section", "article", "header", "footer", "nav", "main", "aside", "form", "address", "body", "html":
		return 1
	}
	return 0
}
