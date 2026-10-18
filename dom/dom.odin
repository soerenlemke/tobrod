package dom

import "core:mem/virtual"
import "core:strings"

// Our own DOM, independent of lexbor. lexbor is only used to parse,
// the result is copied into these types (see parse.odin).

Node_Kind :: enum {
	Document,
	Element,
	Text,
	Comment,
}

Attribute :: struct {
	name:  string,
	value: string,
}

Node :: struct {
	kind:       Node_Kind,
	parent:     ^Node,
	children:   [dynamic]^Node,
	tag:        string,      // Element only, lowercase (e.g. "div")
	attributes: []Attribute, // Element only, in source order
	text:       string,      // Text and Comment only
	style:      Style,       // Element only, defaults + CSS (see style.odin)
	generated:  bool,        // made by us to draw a form control, not from the page (form_controls.odin)
}

// Owns the whole tree. Every node and string lives in the arena,
// so destroy frees everything at once.
Document :: struct {
	arena: virtual.Arena,
	root:  ^Node, // kind == .Document
}

Parse_Error :: struct {
	message: string,
}

destroy :: proc(doc: ^Document) {
	virtual.arena_destroy(&doc.arena)
	free(doc)
}

// Returns ("", false) if the element has no such attribute.
attribute :: proc(node: ^Node, name: string) -> (value: string, ok: bool) {
	for attr in node.attributes {
		if attr.name == name {
			return attr.value, true
		}
	}
	return "", false
}

// The text of the document's <title> with its spaces collapsed (for the tab
// and the window title), "" if it has none. In the temp allocator.
document_title :: proc(doc: ^Document) -> string {
	if doc == nil {
		return ""
	}
	find :: proc(node: ^Node) -> ^Node {
		if node.kind == .Element && node.tag == "title" {
			return node
		}
		if node.kind == .Element && node.tag == "svg" {
			return nil // an SVG's <title> is a tooltip, not the page's
		}
		for child in node.children {
			if found := find(child); found != nil {
				return found
			}
		}
		return nil
	}
	title := find(doc.root)
	if title == nil {
		return ""
	}
	b := strings.builder_make(context.temp_allocator)
	for child in title.children {
		if child.kind == .Text {
			for word in strings.fields(child.text, context.temp_allocator) {
				if strings.builder_len(b) > 0 {
					strings.write_byte(&b, ' ')
				}
				strings.write_string(&b, word)
			}
		}
	}
	return strings.to_string(b)
}
