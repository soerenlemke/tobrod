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
