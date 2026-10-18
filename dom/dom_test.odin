package dom

import "core:testing"

@(test)
test_parse_tree :: proc(t: ^testing.T) {
	doc, err := parse(`<!DOCTYPE html><p class="x">Hi <b>there</b></p><!-- c -->`)
	if e, ok := err.?; ok {
		testing.fail_now(t, e.message)
	}
	defer destroy(doc)

	// lexbor adds the missing <html>, <head> and <body> like a real browser;
	// the doctype is dropped
	tree := tree_to_string(doc.root)
	defer delete(tree)
	expected := `#document
  <html>
    <head>
    <body>
      <p class="x">
        "Hi "
        <b>
          "there"
      <!-- c -->
`
	testing.expect_value(t, tree, expected)
}

@(test)
test_parent_and_attributes :: proc(t: ^testing.T) {
	doc, err := parse(`<a href="/x" hidden>link</a>`)
	if e, ok := err.?; ok {
		testing.fail_now(t, e.message)
	}
	defer destroy(doc)

	html := doc.root.children[0]
	body := html.children[1]
	a := body.children[0]
	testing.expect_value(t, a.tag, "a")
	testing.expect_value(t, a.parent, body)
	testing.expect_value(t, body.parent.parent, doc.root)

	href, ok := attribute(a, "href")
	testing.expect(t, ok, "expected href")
	testing.expect_value(t, href, "/x")
	_, hidden_ok := attribute(a, "hidden")
	testing.expect(t, hidden_ok, "expected valueless attribute")
	_, title_ok := attribute(a, "title")
	testing.expect(t, !title_ok, "expected title to be missing")
}

@(test)
test_parse_display :: proc(t: ^testing.T) {
	cases := []struct {
		value:   string,
		display: Display,
		ok:      bool,
	} {
		{"none", .None, true},
		{"block flow", .Block, true},
		{"flex", .Flex, true},
		{"inline-block", .Inline_Block, true},
		{"inline-flex", .Inline_Flex, true},
		{"inline-grid", .Inline_Grid, true},
		{"grid", .Grid, true},
		{"list-item", .List_Item, true},
		{"ruby", .Inline, false},
	}
	for c in cases {
		display, ok := parse_display(c.value)
		testing.expect_value(t, display, c.display)
		testing.expect_value(t, ok, c.ok)
	}
}

@(test)
test_document_title :: proc(t: ^testing.T) {
	doc, _ := parse("<html><head><title>\n  Hello   tabs \n</title></head><body><svg><title>no</title></svg></body></html>")
	defer destroy(doc)
	testing.expect_value(t, document_title(doc), "Hello tabs")
	empty, _ := parse("<p>no title</p>")
	defer destroy(empty)
	testing.expect_value(t, document_title(empty), "")
}
