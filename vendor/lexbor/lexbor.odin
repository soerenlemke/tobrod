package lexbor

import "core:strings"

when ODIN_OS == .Windows {
	// built from the vendor/lexbor-src submodule by setup.ps1 with the dynamic CRT (/MD).
	// Odin links the static CRT (libcmt) by default, so drop it – same trick as vendor:raylib.
	@(extra_linker_flags = "/NODEFAULTLIB:libcmt")
	foreign import lib "../lexbor-src/build/Release/lexbor_static.lib"
} else {
	foreign import lib "system:lexbor"
}

// Opaque handle. We don't know and don't need the internal layout –
// we just pass the pointer through to lexbor's own functions.
Html_Document :: struct {}

// lexbor's status codes; for now we only need the OK value
Status :: distinct u32
STATUS_OK :: Status(0)

// from lexbor/html/interfaces/document.h
@(default_calling_convention = "c")
foreign lib {
	lxb_html_document_create :: proc() -> ^Html_Document ---
	lxb_html_document_parse :: proc(document: ^Html_Document, html: [^]u8, html_len: uint) -> Status ---
	// returns NULL on success (C: lxb_html_document_t *)
	lxb_html_document_destroy :: proc(document: ^Html_Document) -> ^Html_Document ---
}

// Opaque DOM node (C: lxb_dom_node_t). Every DOM struct in lexbor starts with
// its "parent" struct (html document -> dom document -> dom node), so a pointer
// to a document or element is also a valid node pointer.
Dom_Node :: struct {}

// from lexbor/dom/interfaces/node.h (lxb_dom_node_type_t, a C enum -> 32 bit)
Dom_Node_Type :: enum u32 {
	Undef                  = 0x00,
	Element                = 0x01,
	Attribute              = 0x02,
	Text                   = 0x03,
	Cdata_Section          = 0x04,
	Entity_Reference       = 0x05,
	Entity                 = 0x06,
	Processing_Instruction = 0x07,
	Comment                = 0x08,
	Document               = 0x09,
	Document_Type          = 0x0A,
	Document_Fragment      = 0x0B,
	Notation               = 0x0C,
	Character_Data,
	Shadow_Root,
}

// Same as lexbor's lxb_dom_interface_node macro: a plain pointer cast.
document_node :: proc(document: ^Html_Document) -> ^Dom_Node {
	return cast(^Dom_Node)document
}

// The plain versions of these are `static inline` in the headers and not part of
// the library; the `_noi` ("no inline") variants are exported for bindings.
// All of them return nil when there is no such node.
@(default_calling_convention = "c")
foreign lib {
	// from lexbor/html/interfaces/document.h; really returns lxb_html_body_element_t *,
	// which is a node by the embedding rule above
	lxb_html_document_body_element_noi :: proc(document: ^Html_Document) -> ^Dom_Node ---

	// from lexbor/dom/interfaces/node.h
	lxb_dom_node_first_child_noi :: proc(node: ^Dom_Node) -> ^Dom_Node ---
	lxb_dom_node_last_child_noi :: proc(node: ^Dom_Node) -> ^Dom_Node ---
	lxb_dom_node_next_noi :: proc(node: ^Dom_Node) -> ^Dom_Node ---
	lxb_dom_node_prev_noi :: proc(node: ^Dom_Node) -> ^Dom_Node ---
	lxb_dom_node_parent_noi :: proc(node: ^Dom_Node) -> ^Dom_Node ---
	lxb_dom_node_type_noi :: proc(node: ^Dom_Node) -> Dom_Node_Type ---
}

// Opaque element and attribute (C: lxb_dom_element_t, lxb_dom_attr_t).
// An element starts with its node, so it can only come from an element node,
// see element_from_node.
Dom_Element :: struct {}
Dom_Attr :: struct {}

// All returned strings except text content point into lexbor's memory
// and are valid as long as the document lives. nil means "not there".
@(default_calling_convention = "c")
foreign lib {
	// from lexbor/dom/interfaces/element.h
	lxb_dom_element_local_name :: proc(element: ^Dom_Element, len: ^uint) -> [^]u8 ---
	// lxb_dom_element_get_attribute would be shorter, but returns NULL both for a
	// missing attribute and for one without value, so we look up the attr itself
	lxb_dom_element_attr_by_name :: proc(element: ^Dom_Element, qualified_name: [^]u8, length: uint) -> ^Dom_Attr ---
	lxb_dom_element_first_attribute_noi :: proc(element: ^Dom_Element) -> ^Dom_Attr ---
	lxb_dom_element_next_attribute_noi :: proc(attr: ^Dom_Attr) -> ^Dom_Attr ---

	// from lexbor/dom/interfaces/attr.h
	lxb_dom_attr_local_name_noi :: proc(attr: ^Dom_Attr, len: ^uint) -> [^]u8 ---
	lxb_dom_attr_value_noi :: proc(attr: ^Dom_Attr, len: ^uint) -> [^]u8 ---

	// from lexbor/dom/interfaces/node.h; allocates, free with lxb_dom_document_destroy_text_noi
	lxb_dom_node_text_content :: proc(node: ^Dom_Node, len: ^uint) -> [^]u8 ---
	// from lexbor/dom/interfaces/document.h; really takes lxb_dom_document_t *,
	// which an html document is by the embedding rule
	lxb_dom_document_destroy_text_noi :: proc(document: ^Html_Document, text: [^]u8) -> [^]u8 ---
}

// Returns nil if the node is not an element.
element_from_node :: proc(node: ^Dom_Node) -> ^Dom_Element {
	if node == nil || lxb_dom_node_type_noi(node) != .Element {
		return nil
	}
	return cast(^Dom_Element)node
}

// Lowercase tag name without prefix, e.g. "div". Points into lexbor's memory.
element_name :: proc(element: ^Dom_Element) -> string {
	n: uint
	p := lxb_dom_element_local_name(element, &n)
	return strings.string_from_ptr(p, int(n))
}

// ok is false if the attribute is missing; an attribute without value
// (e.g. <input disabled>) gives ("", true). Points into lexbor's memory.
element_attribute :: proc(element: ^Dom_Element, name: string) -> (value: string, ok: bool) {
	attr := lxb_dom_element_attr_by_name(element, raw_data(name), uint(len(name)))
	if attr == nil {
		return "", false
	}
	return attr_value(attr), true
}

attr_name :: proc(attr: ^Dom_Attr) -> string {
	n: uint
	p := lxb_dom_attr_local_name_noi(attr, &n)
	return strings.string_from_ptr(p, int(n))
}

attr_value :: proc(attr: ^Dom_Attr) -> string {
	n: uint
	p := lxb_dom_attr_value_noi(attr, &n)
	return strings.string_from_ptr(p, int(n))
}

// Concatenated text of the node and all descendants. Unlike the other helpers
// this returns a copy owned by the caller, because lexbor allocates the text
// separately and we free its buffer right away.
node_text_content :: proc(document: ^Html_Document, node: ^Dom_Node, allocator := context.allocator) -> string {
	n: uint
	p := lxb_dom_node_text_content(node, &n)
	if p == nil {
		return ""
	}
	defer lxb_dom_document_destroy_text_noi(document, p)
	return strings.clone(strings.string_from_ptr(p, int(n)), allocator)
}
