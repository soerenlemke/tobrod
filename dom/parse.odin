package dom

import "core:mem"
import "core:mem/virtual"
import "core:strings"
import lxb "../vendor/lexbor"

// Parses html with lexbor and copies the result into our own tree.
// The lexbor document is destroyed before returning, so nothing points into it.
parse :: proc(html: string) -> (doc: ^Document, err: Maybe(Parse_Error)) {
	lxb_doc := lxb.lxb_html_document_create()
	if lxb_doc == nil {
		return nil, Parse_Error{"lexbor: could not create document"}
	}
	defer lxb.lxb_html_document_destroy(lxb_doc)

	// Must happen before parsing: lexbor then reads <style> and style=""
	// while parsing and runs the cascade for us.
	if status := lxb.lxb_style_init(lxb_doc); status != lxb.STATUS_OK {
		return nil, Parse_Error{"lexbor: could not init CSS"}
	}
	// defers run in reverse order, so this runs before the document is destroyed
	defer lxb.lxb_style_destroy(lxb_doc)

	if status := lxb.lxb_html_document_parse(lxb_doc, raw_data(html), uint(len(html))); status != lxb.STATUS_OK {
		return nil, Parse_Error{"lexbor: parsing failed"}
	}

	doc = new(Document)
	if alloc_err := virtual.arena_init_growing(&doc.arena); alloc_err != nil {
		free(doc)
		return nil, Parse_Error{"could not create arena"}
	}
	allocator := virtual.arena_allocator(&doc.arena)

	doc.root = new(Node, allocator)
	doc.root.kind = .Document
	doc.root.children.allocator = allocator
	copy_children(lxb_doc, lxb.document_node(lxb_doc), doc.root, allocator)
	return doc, nil
}

// Recursive copy. Fine for a toy browser; very deeply nested pages
// could exhaust the stack.
@(private)
copy_children :: proc(lxb_doc: ^lxb.Html_Document, from: ^lxb.Dom_Node, to: ^Node, allocator: mem.Allocator) {
	for child := lxb.lxb_dom_node_first_child_noi(from); child != nil; child = lxb.lxb_dom_node_next_noi(child) {
		node: ^Node
		#partial switch lxb.lxb_dom_node_type_noi(child) {
		case .Element:
			node = new_node(.Element, to, allocator)
			element := lxb.element_from_node(child)
			node.tag = strings.clone(lxb.element_name(element), allocator)
			node.attributes = copy_attributes(element, allocator)
			node.style = compute_style(node, element)
			copy_children(lxb_doc, child, node, allocator)
		case .Text:
			node = new_node(.Text, to, allocator)
			node.text = lxb.node_text_content(lxb_doc, child, allocator)
		case .Comment:
			node = new_node(.Comment, to, allocator)
			node.text = lxb.node_text_content(lxb_doc, child, allocator)
		case:
			// doctype, processing instructions, ... are not needed for rendering
		}
	}
}

@(private)
new_node :: proc(kind: Node_Kind, parent: ^Node, allocator: mem.Allocator) -> ^Node {
	node := new(Node, allocator)
	node.kind = kind
	node.parent = parent
	node.children.allocator = allocator
	append(&parent.children, node)
	return node
}

@(private)
copy_attributes :: proc(element: ^lxb.Dom_Element, allocator: mem.Allocator) -> []Attribute {
	count := 0
	for attr := lxb.lxb_dom_element_first_attribute_noi(element); attr != nil; attr = lxb.lxb_dom_element_next_attribute_noi(attr) {
		count += 1
	}

	attributes := make([]Attribute, count, allocator)
	i := 0
	for attr := lxb.lxb_dom_element_first_attribute_noi(element); attr != nil; attr = lxb.lxb_dom_element_next_attribute_noi(attr) {
		attributes[i] = Attribute{
			name  = strings.clone(lxb.attr_name(attr), allocator),
			value = strings.clone(lxb.attr_value(attr), allocator),
		}
		i += 1
	}
	return attributes
}

// Default style for the tag, overridden by whatever the CSS cascade decided.
@(private)
compute_style :: proc(node: ^Node, element: ^lxb.Dom_Element) -> Style {
	_, hidden := attribute(node, "hidden")
	style := default_style(node.tag, hidden)

	if value, ok := lxb.element_style(element, "display", context.temp_allocator); ok {
		if display, known := parse_display(value); known {
			style.display = display
		}
	}
	return style
}
