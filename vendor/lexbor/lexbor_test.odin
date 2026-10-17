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
