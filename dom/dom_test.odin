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
test_display_text :: proc(t: ^testing.T) {
	doc, err := parse(`<html><head><title>T</title><style>p{}</style></head><body>
  <h1>Title</h1>
  <p>Some   <b>bold</b>
     text.<br>Next line</p>
  <script>var x = 1;</script>
  <ul><li>one</li><li>two</li></ul>
  <pre>a  b
c</pre>
  <div>end</div>
</body></html>`)
	if e, ok := err.?; ok {
		testing.fail_now(t, e.message)
	}
	defer destroy(doc)

	text := to_display_text(doc)
	defer delete(text)
	expected := "Title\n\nSome bold text.\nNext line\n\n• one\n• two\n\na  b\nc\n\nend"
	testing.expect_value(t, text, expected)
}
