package lexbor

import "core:testing"

@(test)
test_parse_simple_html :: proc(t: ^testing.T) {
	doc := lxb_html_document_create()
	defer lxb_html_document_destroy(doc)

	html := "<html><body>Hello</body></html>"
	status := lxb_html_document_parse(doc, raw_data(transmute([]u8)html), len(html))

	testing.expect(t, status == STATUS_OK, "expected parsing to succeed")
}

@(test)
test_traverse_dom :: proc(t: ^testing.T) {
	doc := lxb_html_document_create()
	defer lxb_html_document_destroy(doc)

	html := "<html><body><p>a</p><!-- c --><p>b</p></body></html>"
	status := lxb_html_document_parse(doc, raw_data(transmute([]u8)html), len(html))
	testing.expect(t, status == STATUS_OK, "expected parsing to succeed")

	root := document_node(doc)
	testing.expect_value(t, lxb_dom_node_type_noi(root), Dom_Node_Type.Document)

	// document -> <html> element
	html_el := lxb_dom_node_first_child_noi(root)
	testing.expect_value(t, lxb_dom_node_type_noi(html_el), Dom_Node_Type.Element)
	testing.expect_value(t, lxb_dom_node_parent_noi(html_el), root)

	body := lxb_html_document_body_element_noi(doc)
	testing.expect(t, body != nil, "expected a body element")

	// body children: <p>, comment, <p>
	types: [dynamic]Dom_Node_Type
	defer delete(types)
	for child := lxb_dom_node_first_child_noi(body); child != nil; child = lxb_dom_node_next_noi(child) {
		append(&types, lxb_dom_node_type_noi(child))
	}
	testing.expect_value(t, len(types), 3)
	if len(types) == 3 {
		testing.expect_value(t, types[0], Dom_Node_Type.Element)
		testing.expect_value(t, types[1], Dom_Node_Type.Comment)
		testing.expect_value(t, types[2], Dom_Node_Type.Element)
	}

	// <p> -> text "a"; walking backwards from the last child ends at the first one
	first_p := lxb_dom_node_first_child_noi(body)
	testing.expect_value(t, lxb_dom_node_type_noi(lxb_dom_node_first_child_noi(first_p)), Dom_Node_Type.Text)
	last_p := lxb_dom_node_last_child_noi(body)
	testing.expect_value(t, lxb_dom_node_prev_noi(lxb_dom_node_prev_noi(last_p)), first_p)
	testing.expect(t, lxb_dom_node_prev_noi(first_p) == nil, "first child has no previous sibling")
}

@(test)
test_node_data :: proc(t: ^testing.T) {
	doc := lxb_html_document_create()
	defer lxb_html_document_destroy(doc)

	html := `<html><body><a href="/x" id="link" hidden>Hi <b>there</b></a></body></html>`
	status := lxb_html_document_parse(doc, raw_data(transmute([]u8)html), len(html))
	testing.expect(t, status == STATUS_OK, "expected parsing to succeed")

	body := lxb_html_document_body_element_noi(doc)
	testing.expect_value(t, element_name(element_from_node(body)), "body")

	link_node := lxb_dom_node_first_child_noi(body)
	link := element_from_node(link_node)
	testing.expect(t, link != nil, "expected <a> to be an element")
	testing.expect_value(t, element_name(link), "a")

	// lookup by name
	href, ok := element_attribute(link, "href")
	testing.expect(t, ok, "expected href")
	testing.expect_value(t, href, "/x")
	hidden, hidden_ok := element_attribute(link, "hidden")
	testing.expect(t, hidden_ok, "expected valueless attribute to be present")
	testing.expect_value(t, hidden, "")
	_, missing_ok := element_attribute(link, "title")
	testing.expect(t, !missing_ok, "expected title to be missing")

	// iteration keeps source order
	names: [dynamic]string
	defer delete(names)
	for attr := lxb_dom_element_first_attribute_noi(link); attr != nil; attr = lxb_dom_element_next_attribute_noi(attr) {
		append(&names, attr_name(attr))
	}
	testing.expect_value(t, len(names), 3)
	if len(names) == 3 {
		testing.expect_value(t, names[0], "href")
		testing.expect_value(t, names[1], "id")
		testing.expect_value(t, names[2], "hidden")
	}

	// text of an element includes its descendants
	text := node_text_content(doc, link_node)
	defer delete(text)
	testing.expect_value(t, text, "Hi there")

	// a text node is not an element
	testing.expect(t, element_from_node(lxb_dom_node_first_child_noi(link_node)) == nil, "text node is no element")
}
