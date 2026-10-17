package dom

import "core:mem/virtual"

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
