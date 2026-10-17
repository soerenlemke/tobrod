package lexbor

import "base:runtime"
import "core:strings"

// CSS support (lexbor's css + style modules). After style_init, lexbor parses
// <style> elements and style="" attributes itself and runs the cascade
// (selector matching, specificity, !important, source order). For every element
// we can then ask for the declaration that won.

// Start of lxb_css_rule_t (css/rule.h). Only mirrored so that the offset of the
// fields after it in Css_Rule_Declaration is right.
Css_Rule :: struct {
	type:      u32, // lxb_css_rule_type_t, a C enum
	next:      rawptr,
	prev:      rawptr,
	parent:    rawptr,
	memory:    rawptr,
	ref_count: uint,
}

// Start of lxb_css_rule_declaration_t (css/rule.h). We only read type and value,
// so the fields after them are left out. Has to match lexbor's layout:
// check css/rule.h when updating the lexbor submodule.
Css_Rule_Declaration :: struct {
	rule:  Css_Rule,
	type:  uintptr, // lxb_css_property_type_t, e.g. the id of "color"
	value: rawptr,  // union u: points to the typed property struct
}

// lexbor_serialize_cb_f (core/base.h)
Serialize_Cb :: #type proc "c" (data: [^]u8, len: uint, ctx: rawptr) -> Status

@(default_calling_convention = "c")
foreign lib {
	// from lexbor/style/style.h; call before parsing, destroy before the document
	lxb_style_init :: proc(document: ^Html_Document) -> Status ---
	lxb_style_destroy :: proc(document: ^Html_Document) ---

	// from lexbor/style/dom/interfaces/element.h; nil if no rule sets the property
	lxb_dom_element_style_by_name :: proc(element: ^Dom_Element, name: [^]u8, size: uint) -> ^Css_Rule_Declaration ---

	// from lexbor/css/property.h; writes only the value, e.g. "red" or "12px"
	lxb_css_property_serialize :: proc(style: rawptr, type: uintptr, cb: Serialize_Cb, ctx: rawptr) -> Status ---
}

// The value that won the cascade for a property, e.g. element_style(el, "color") -> "red".
// ok is false if no rule sets it. Inherited and default values are not included,
// lexbor only knows what was declared for this element.
// The returned string is allocated with the given allocator.
element_style :: proc(element: ^Dom_Element, property: string, allocator := context.allocator) -> (value: string, ok: bool) {
	declaration := lxb_dom_element_style_by_name(element, raw_data(property), uint(len(property)))
	if declaration == nil {
		return "", false
	}

	b := strings.builder_make(allocator)
	status := lxb_css_property_serialize(declaration.value, declaration.type, write_to_builder, &b)
	if status != STATUS_OK {
		strings.builder_destroy(&b)
		return "", false
	}
	return strings.to_string(b), true
}

// C callback: lexbor hands us the serialized value in pieces.
@(private)
write_to_builder :: proc "c" (data: [^]u8, len: uint, ctx: rawptr) -> Status {
	context = runtime.default_context()
	b := cast(^strings.Builder)ctx
	strings.write_string(b, strings.string_from_ptr(data, int(len)))
	return STATUS_OK
}

// Stylesheets from outside the HTML (<link rel="stylesheet">): we parse the CSS
// text ourselves and attach the result to the document; from then on its
// rules take part in the cascade like those of <style> elements.

// Opaque (C: lxb_css_parser_t, lxb_css_stylesheet_t)
Css_Parser :: struct {}
Css_Stylesheet :: struct {}

@(default_calling_convention = "c")
foreign lib {
	// from lexbor/css/parser.h; tokenizer nil = create its own
	lxb_css_parser_create :: proc() -> ^Css_Parser ---
	lxb_css_parser_init :: proc(parser: ^Css_Parser, tokenizer: rawptr) -> Status ---
	lxb_css_parser_destroy :: proc(parser: ^Css_Parser, self_destroy: bool) -> ^Css_Parser ---

	// from lexbor/css/stylesheet.h; memory nil = create its own
	lxb_css_stylesheet_create :: proc(memory: rawptr) -> ^Css_Stylesheet ---
	lxb_css_stylesheet_parse :: proc(sst: ^Css_Stylesheet, parser: ^Css_Parser, data: [^]u8, length: uint) -> Status ---
	lxb_css_stylesheet_destroy :: proc(sst: ^Css_Stylesheet, destroy_memory: bool) -> ^Css_Stylesheet ---

	// from lexbor/style/html/interfaces/document.h; the stylesheet must stay
	// alive as long as the document uses it
	lxb_html_document_stylesheet_attach_noi :: proc(document: ^Html_Document, sst: ^Css_Stylesheet) -> Status ---

	// from lexbor/style/html/interfaces/style_element.h: takes the rules of a
	// <style> element (which lexbor applies while parsing) out of the cascade.
	// element must be a <style> element.
	lxb_html_style_element_remove :: proc(element: ^Dom_Element) -> Status ---
}

// Walking all declarations of an element (lexbor/style/dom/interfaces/element.h).
// lexbor calls the callback once per declaration that applies to the element.
// is_weak: the declaration lost the cascade against another one for the same
// property. spec is the specificity (with !important and style="" in the top bits).
Style_Walk_Cb :: #type proc "c" (element: ^Dom_Element, declaration: ^Css_Rule_Declaration, ctx: rawptr, spec: u32, is_weak: bool) -> Status

@(default_calling_convention = "c")
foreign lib {
	lxb_dom_element_style_walk :: proc(element: ^Dom_Element, cb: Style_Walk_Cb, ctx: rawptr, with_weak: bool) -> Status ---
	// from lexbor/css/property.h; writes the property name, e.g. "color" or "--main"
	lxb_css_property_serialize_name :: proc(style: rawptr, type: uintptr, cb: Serialize_Cb, ctx: rawptr) -> Status ---
}
