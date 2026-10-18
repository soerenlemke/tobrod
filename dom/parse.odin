package dom

import "core:mem"
import "core:mem/virtual"
import "core:strings"
import lxb "../vendor/lexbor"

// Fetches an external stylesheet for parse. href is written like in the page
// or stylesheet (relative); base is the URL of the stylesheet it is in (for
// @import), "" for the page itself. Resolving and loading is up to the
// caller, so dom stays free of networking. href and base are only valid
// during the call (href points into lexbor's memory), copy them to keep them.
// Returns the CSS and the URL it came from (after redirects, the base for its
// own @imports); both only have to live until the next call.
Stylesheet_Loader :: struct {
	load: proc(ctx: rawptr, href, base: string) -> (css, url: string, ok: bool),
	ctx:  rawptr,
}

// Parses html with lexbor and copies the result into our own tree.
// With a stylesheet loader, <link rel="stylesheet"> files are fetched and take
// part in the cascade; like in a browser they block until they are there
// ("render-blocking"), so the page never shows up unstyled first.
// @media blocks (which lexbor skips) are evaluated for the given viewport,
// in external stylesheets and in <style> elements, see media.odin.
// The lexbor document is destroyed before returning, so nothing points into it.
// report: if given, the CSS we don't support is counted there (css_report.odin).
parse :: proc(html: string, stylesheets: Stylesheet_Loader = {}, media := DEFAULT_MEDIA, report: ^Css_Report = nil) -> (doc: ^Document, err: Maybe(Parse_Error)) {
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

	// stylesheets we attach to the document, before the styles are read in
	// copy_children
	sheets := Sheets{lxb_doc = lxb_doc, loader = stylesheets, media = media}
	defer sheets_destroy(&sheets) // runs before the document is destroyed

	// <style> elements: lexbor applied them while parsing, but without their
	// @media blocks and @imports. Add the imported stylesheets (they end up
	// after the element's own rules, not before) and the matching @media blocks.
	style_texts := make([dynamic]string, context.temp_allocator)
	find_style_elements(lxb_doc, lxb.document_node(lxb_doc), media, &style_texts)
	for text in style_texts {
		imports, rest := split_imports(text)
		for imp in imports {
			if media_query_list_matches(imp.media, media) {
				sheets_load(&sheets, imp.href, "", 1)
			}
		}
		sheets_add(&sheets, apply_media_queries(rest, media, only_media = true, allocator = context.temp_allocator))
	}

	// external stylesheets, in document order
	hrefs := make([dynamic]string, context.temp_allocator)
	find_stylesheet_links(lxb.document_node(lxb_doc), media, &hrefs)
	for href in hrefs {
		sheets_load(&sheets, href, "", 0)
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
	doc.root.style = ROOT_STYLE
	root_props := make(Custom_Props, allocator = context.temp_allocator)
	copy_children(lxb_doc, lxb.document_node(lxb_doc), doc.root, &root_props, allocator, report)
	return doc, nil
}

// Recursive copy. Fine for a toy browser; very deeply nested pages
// could exhaust the stack.
@(private)
// props: the custom properties (CSS variables) inherited from the parent.
copy_children :: proc(lxb_doc: ^lxb.Html_Document, from: ^lxb.Dom_Node, to: ^Node, props: ^Custom_Props, allocator: mem.Allocator, report: ^Css_Report) {
	for child := lxb.lxb_dom_node_first_child_noi(from); child != nil; child = lxb.lxb_dom_node_next_noi(child) {
		node: ^Node
		#partial switch lxb.lxb_dom_node_type_noi(child) {
		case .Element:
			node = new_node(.Element, to, allocator)
			element := lxb.element_from_node(child)
			node.tag = strings.clone(lxb.element_name(element), allocator)
			node.attributes = copy_attributes(element, allocator)
			own_props: ^Custom_Props
			node.style, own_props = compute_style(node, element, to.style, props, report)
			if report != nil {
				report_node(report, node)
			}
			copy_children(lxb_doc, child, node, own_props, allocator, report)
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

// Inherited values and tag defaults, overridden by whatever the CSS cascade
// decided. Parents are computed before their children, so parent is final.
@(private)
compute_style :: proc(node: ^Node, element: ^lxb.Dom_Element, parent: Style, inherited_props: ^Custom_Props, report: ^Css_Report = nil) -> (style: Style, props: ^Custom_Props) {
	_, hidden := attribute(node, "hidden")
	style = default_style(node.tag, hidden, parent)

	// custom properties and declarations with var(), see custom_props.odin
	declared := walk_declarations(element)
	props = element_custom_props(inherited_props, &declared)
	if report != nil {
		report_element(report, element, &declared, props)
	}
	raw_values := winning_raw_declarations(&declared, props)

	for property in STYLE_PROPERTIES {
		// a longhand loses against a more specific shorthand that was applied
		// before it (`.menu ul { list-style: none }` vs `ul { list-style-type: disc }`)
		if loses_to_shorthand(&declared, property) {
			continue
		}
		if value, ok := lxb.element_style(element, property, context.temp_allocator); ok {
			apply_declaration(&style, property, value, parent)
		}
		// a raw value that won (var() or something lexbor can't parse) on top;
		// if our parsers reject it too, the typed value above stays
		if value, ok := raw_values[property]; ok {
			apply_declaration(&style, property, value, parent)
		}
	}
	// floated elements and the children of a flex container are always
	// block-level (CSS "blockification"); floats don't apply to flex items
	if style.float != .None || is_flex_container(parent.display) {
		#partial switch style.display {
		case .Inline, .Inline_Block, .Table_Cell, .Table_Row:
			style.display = .Block
		case .Inline_Flex:
			style.display = .Flex
		}
	}
	if is_flex_container(parent.display) {
		style.float = .None
	}
	propagate_decoration(&style, parent)
	return
}

// Collects the hrefs of <link rel="stylesheet"> in document order. Print-only
// stylesheets are skipped. (Other media queries are not evaluated yet.)
@(private)
find_stylesheet_links :: proc(node: ^lxb.Dom_Node, env: Media_Env, hrefs: ^[dynamic]string) {
	for child := lxb.lxb_dom_node_first_child_noi(node); child != nil; child = lxb.lxb_dom_node_next_noi(child) {
		if element := lxb.element_from_node(child); element != nil {
			if lxb.element_name(element) == "link" && is_stylesheet_link(element, env) {
				if href, ok := lxb.element_attribute(element, "href"); ok && href != "" {
					append(hrefs, href)
				}
			}
			find_stylesheet_links(child, env, hrefs)
		}
	}
}

@(private)
is_stylesheet_link :: proc(element: ^lxb.Dom_Element, env: Media_Env) -> bool {
	rel := lxb.element_attribute(element, "rel") or_return
	// rel is a space separated list, e.g. "alternate stylesheet" (which we skip)
	is_stylesheet, is_alternate := false, false
	rest := rel
	for word in strings.fields_iterator(&rest) {
		switch strings.to_lower(word, context.temp_allocator) {
		case "stylesheet":
			is_stylesheet = true
		case "alternate":
			is_alternate = true
		}
	}
	if !is_stylesheet || is_alternate {
		return false
	}
	// media="print", media="(prefers-color-scheme: dark)", ...: only if it
	// matches, like an @media block around the whole stylesheet
	media, has_media := lxb.element_attribute(element, "media")
	return !has_media || media_query_list_matches(media, env)
}

// Collects the text of <style> elements that contain @media or @import (the
// others are fully handled by lexbor already). lexbor ignores the media attribute of
// <style>, so elements whose media doesn't match are taken out of the cascade.
@(private)
find_style_elements :: proc(lxb_doc: ^lxb.Html_Document, node: ^lxb.Dom_Node, env: Media_Env, texts: ^[dynamic]string) {
	for child := lxb.lxb_dom_node_first_child_noi(node); child != nil; child = lxb.lxb_dom_node_next_noi(child) {
		if element := lxb.element_from_node(child); element != nil {
			if lxb.element_name(element) == "style" {
				// <style media="print">: lexbor applied it anyway, take it out again
				if media, ok := lxb.element_attribute(element, "media"); ok && !media_query_list_matches(media, env) {
					lxb.lxb_html_style_element_remove(element)
					continue
				}
				text := lxb.node_text_content(lxb_doc, child, context.temp_allocator)
				lower := strings.to_lower(text, context.temp_allocator)
				if strings.contains(lower, "@media") || strings.contains(lower, "@import") {
					append(texts, text)
				}
				continue
			}
			find_style_elements(lxb_doc, child, env, texts)
		}
	}
}

// The stylesheets parse attaches to the lexbor document: external ones, the
// ones they @import, and the @media parts of <style> elements.
@(private)
Sheets :: struct {
	lxb_doc: ^lxb.Html_Document,
	parser:  ^lxb.Css_Parser,
	list:    [dynamic]^lxb.Css_Stylesheet,
	loader:  Stylesheet_Loader,
	media:   Media_Env,
}

@(private)
sheets_destroy :: proc(s: ^Sheets) {
	// like in lexbor's own example: the stylesheets before the document
	for sheet in s.list {
		lxb.lxb_css_stylesheet_destroy(sheet, true)
	}
	delete(s.list)
	if s.parser != nil {
		lxb.lxb_css_parser_destroy(s.parser, true)
	}
}

// Parses css and attaches it to the document (after everything before).
@(private)
sheets_add :: proc(s: ^Sheets, css: string) {
	if css == "" {
		return
	}
	if s.parser == nil {
		s.parser = lxb.lxb_css_parser_create()
		if lxb.lxb_css_parser_init(s.parser, nil) != lxb.STATUS_OK {
			return
		}
	}
	sheet := lxb.lxb_css_stylesheet_create(nil)
	if lxb.lxb_css_stylesheet_parse(sheet, s.parser, raw_data(css), uint(len(css))) != lxb.STATUS_OK {
		lxb.lxb_css_stylesheet_destroy(sheet, true)
		return
	}
	lxb.lxb_html_document_stylesheet_attach_noi(s.lxb_doc, sheet)
	append(&s.list, sheet)
}

// Loads an external stylesheet: first the stylesheets it @imports (their
// rules come first in the cascade), then its own rules.
@(private)
sheets_load :: proc(s: ^Sheets, href, base: string, depth: int) {
	if s.loader.load == nil || depth > MAX_IMPORT_DEPTH {
		return
	}
	css, url, ok := s.loader.load(s.loader.ctx, href, base)
	if !ok {
		return // a missing stylesheet doesn't stop the page
	}
	// the loader's buffers are reused by the next request (an @import)
	css = strings.clone(css, context.temp_allocator)
	url = strings.clone(url, context.temp_allocator)

	imports, rest := split_imports(css)
	for imp in imports {
		if media_query_list_matches(imp.media, s.media) {
			sheets_load(s, imp.href, url, depth + 1)
		}
	}
	sheets_add(s, apply_media_queries(rest, s.media, allocator = context.temp_allocator))
}
