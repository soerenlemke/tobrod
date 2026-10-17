package layout

import "core:testing"
import "../dom"

@(private = "file")
build_table :: proc(t: ^testing.T, html: string, width: f32) -> (doc: ^dom.Document, l: ^Layout) {
	err: Maybe(dom.Parse_Error)
	doc, err = dom.parse(html)
	if e, ok := err.?; ok {
		testing.fail_now(t, e.message)
	}
	return doc, build(doc, {width, 600}, fake_measure)
}

@(private = "file")
run_by_text :: proc(l: ^Layout, text: string) -> (Text_Run, bool) {
	for run in l.runs {
		if run.text == text {
			return run, true
		}
	}
	return {}, false
}

@(test)
test_table_auto_width :: proc(t: ^testing.T) {
	// cells: 1px padding (UA), 2px spacing between and around them
	// column 0: max("aa" 16, "c" 8) + 2 = 18, column 1: "bbbb" 32 + 2 = 34
	doc, l := build_table(t, `<table><tr><td>aa</td><td>bbbb</td></tr><tr><td>c</td><td>d</td></tr></table>`, 416)
	defer dom.destroy(doc)
	defer destroy(l)

	aa, _ := run_by_text(l, "aa")
	bbbb, _ := run_by_text(l, "bbbb")
	c, _ := run_by_text(l, "c")
	// table at body content (8, 8); first cell at 8 + 2 spacing, content +1 padding
	testing.expect_value(t, aa.x, 11)
	testing.expect_value(t, bbbb.x, 8 + 2 + 18 + 2 + 1)
	// row 1: top 10, text in its 20px line box at 10 + 1 + 2; row height 22
	testing.expect_value(t, aa.y, 13)
	// row 2 starts after row 1 + spacing: 10 + 22 + 2
	testing.expect_value(t, c.y, 34 + 3)
	testing.expect_value(t, c.x, 11)
	// table ends after row 2 + spacing (58), plus the body margin
	testing.expect_value(t, l.height, 58 + 8)
}

@(test)
test_table_wraps_and_distributes :: proc(t: ^testing.T) {
	// 400px for the table: "short" (5 chars) and a long text (60 chars = 480px)
	// don't fit at max-content. min: 42 and 66 ("abcdefgh" 64 + 2), max: 42 and 482.
	LONG :: "abcdefgh abcdefgh abcdefgh abcdefgh abcdefgh abcdefgh abcdefg"
	doc, l := build_table(t, `<table><tr><td>short</td><td>` + LONG + `</td></tr></table>`, 416)
	defer dom.destroy(doc)
	defer destroy(l)

	// columns get 400 - 3*2 spacing = 394: column 0 keeps its 42 (min == max),
	// column 1 gets the rest
	first, _ := run_by_text(l, "abcdefgh abcdefgh abcdefgh abcdefgh")
	testing.expect_value(t, first.x, 8 + 2 + 42 + 2 + 1)
	// the long cell wrapped: it has more than one line, so "short" is centered
	// vertically against it (vertical-align: middle)
	short, _ := run_by_text(l, "short")
	lines := 0
	for run in l.runs {
		if run.x == first.x {
			lines += 1
		}
	}
	testing.expect(t, lines == 2, "the long cell wraps onto two lines")
	testing.expect_value(t, short.y, first.y + 10)
}

@(test)
test_table_colspan_and_boxes :: proc(t: ^testing.T) {
	doc, l := build_table(t, `<table style="border-collapse: collapse; width: 200px"><thead><tr><th colspan="2" style="background: #eee">head</th></tr></thead>
		<tbody><tr><td style="border: 1px solid black">a</td><td>b</td></tr></tbody></table>`, 416)
	defer dom.destroy(doc)
	defer destroy(l)

	// two boxes: the th background and the td border
	testing.expect_value(t, len(l.boxes), 2)
	if len(l.boxes) != 2 do return
	head := l.boxes[0]
	// border-collapse: no spacing; the th spans the whole 200px table
	testing.expect_value(t, head.x, 8)
	testing.expect_value(t, head.width, 200)
	// th is centered (UA) in its cell
	text, _ := run_by_text(l, "head")
	testing.expect_value(t, text.x, 8 + (200 - 32) / 2)

	cell := l.boxes[1]
	testing.expect_value(t, cell.y, head.y + head.height)
	testing.expect_value(t, cell.border[.Left], 1)
	// max-content: "a" 8 + 2 padding + 2 border = 12, "b" 10; the th needs 34,
	// so both get 6 more: 18 and 16. The extra space of the 200px table (166)
	// is shared in proportion to that: 18 + 166 * 18/34
	testing.expect(t, abs(cell.width - (18 + 166.0 * 18 / 34)) < 0.01, "column width in proportion to max-content")
}

@(test)
test_table_anonymous_cell_and_bottom_caption :: proc(t: ^testing.T) {
	// Wikipedia's image markup: a table without rows, the caption below
	doc, l := build_table(t, `<figure style="display: table; margin: 0">
		<a href="x"><img src="i.png" width="100" height="50"></a>
		<figcaption style="display: table-caption; caption-side: bottom">a caption</figcaption>
	</figure>`, 416)
	defer dom.destroy(doc)
	defer destroy(l)

	// the image sits in an anonymous cell; the table is as wide as it (+ spacing)
	testing.expect_value(t, len(l.images), 1)
	if len(l.images) != 1 do return
	image := l.images[0]
	testing.expect_value(t, image.x, 8 + 2)
	testing.expect_value(t, image.link, "x")

	// the caption comes below the image and wraps to the table width (104):
	// "a caption" is 72px wide and fits
	caption, ok := run_by_text(l, "a caption")
	testing.expect(t, ok, "caption on one line")
	testing.expect(t, caption.y > image.y + image.height, "caption below the image")
}

@(test)
test_table_measure_ignores_text_align :: proc(t: ^testing.T) {
	// a centered table cell must not be measured as if centered in an
	// "infinitely" wide line
	doc, l := build_table(t, `<table style="text-align: center; border: 1px solid black"><tr><td>abc</td></tr></table>`, 416)
	defer dom.destroy(doc)
	defer destroy(l)
	if len(l.boxes) != 1 do return
	// 1 border + 2 spacing + (24 + 2 padding) + 2 spacing + 1 border
	testing.expect_value(t, l.boxes[0].width, 32)
}
