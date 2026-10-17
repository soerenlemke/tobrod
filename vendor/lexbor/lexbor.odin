package lexbor

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
