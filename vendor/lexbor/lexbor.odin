package lexbor

when ODIN_OS == .Darwin {
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
	lxb_html_document_destroy :: proc(document: ^Html_Document) -> Html_Document ---
}
