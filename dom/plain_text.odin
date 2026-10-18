package dom

import "core:mem/virtual"
import "core:strings"

// Wraps plain text into a document like Chrome does for text/plain:
// <html><body><pre>text</pre></body></html>. So plain text and HTML take
// the same path through layout and rendering.
from_plain_text :: proc(text: string) -> (doc: ^Document, err: Maybe(Parse_Error)) {
	doc = new(Document)
	if alloc_err := virtual.arena_init_growing(&doc.arena); alloc_err != nil {
		free(doc)
		return nil, Parse_Error{"could not create arena"}
	}
	allocator := virtual.arena_allocator(&doc.arena)

	doc.root = new(Node, allocator)
	doc.root.kind = .Document
	doc.root.children.allocator = allocator
	doc.root.style = ROOT_STYLE

	parent := doc.root
	for tag in ([]string{"html", "body", "pre"}) {
		element := new_node(.Element, parent, allocator)
		element.tag = tag
		element.style = default_style(tag, false, parent.style)
		parent = element
	}
	// long lines wrap, like in Chrome (its text/plain style is pre-wrap)
	parent.style.white_space = .Pre_Wrap

	text_node := new_node(.Text, parent, allocator)
	text_node.text = strings.clone(text, allocator)
	return doc, nil
}
