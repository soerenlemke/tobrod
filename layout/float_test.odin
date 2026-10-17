package layout

import "core:testing"
import "../dom"

@(private = "file")
build_floats :: proc(t: ^testing.T, html: string) -> (doc: ^dom.Document, l: ^Layout) {
	err: Maybe(dom.Parse_Error)
	doc, err = dom.parse(html)
	if e, ok := err.?; ok {
		testing.fail_now(t, e.message)
	}
	return doc, build(doc, {416, 600}, fake_measure) // body content: x 8..408
}

// 30 words of 4 chars = many lines at 8px per char
@(private = "file")
TEXT :: "aaaa aaaa aaaa aaaa aaaa aaaa aaaa aaaa aaaa aaaa aaaa aaaa aaaa aaaa aaaa aaaa aaaa aaaa aaaa aaaa aaaa aaaa aaaa aaaa aaaa aaaa aaaa aaaa aaaa aaaa"

@(test)
test_float_right_text_flows_around :: proc(t: ^testing.T) {
	doc, l := build_floats(t, `<img src="i.png" width="100" height="60" style="float: right"><p style="margin: 0">` + TEXT + `</p>`)
	defer dom.destroy(doc)
	defer destroy(l)

	if len(l.images) != 1 do return
	image := l.images[0]
	testing.expect_value(t, image.x, 408 - 100)
	testing.expect_value(t, image.y, 8)

	// lines next to the image end before it, lines below it use the full width
	beside, below := false, false
	for run in l.runs {
		if run.y < image.y + image.height {
			testing.expectf(t, run.x + run.width <= image.x, "run at y %v overlaps the float", run.y)
			beside = true
		} else if run.x + run.width > image.x {
			below = true
		}
	}
	testing.expect(t, beside && below, "text next to and below the float")
}

@(test)
test_float_left_and_clear :: proc(t: ^testing.T) {
	// (height is not supported for blocks yet, so the float gets two lines of content)
	doc, l := build_floats(t, `<div style="float: left; width: 50px">x<br>x</div><p style="margin: 0">beside</p><p style="clear: left; margin: 0">below</p>`)
	defer dom.destroy(doc)
	defer destroy(l)

	beside, _ := find_run(l, "beside")
	below, _ := find_run(l, "below")
	testing.expect_value(t, beside.x, 8 + 50)
	testing.expect_value(t, beside.y, 8 + 2)
	// clear: left puts the paragraph below the 40px high float
	testing.expect_value(t, below.x, 8)
	testing.expect_value(t, below.y, 8 + 40 + 2)
}

@(test)
test_float_shrink_to_fit :: proc(t: ^testing.T) {
	doc, l := build_floats(t, `<div style="float: left; border: 1px solid black; padding: 2px">abc</div>text`)
	defer dom.destroy(doc)
	defer destroy(l)

	testing.expect_value(t, len(l.boxes), 1)
	if len(l.boxes) != 1 do return
	box := l.boxes[0]
	// as wide as its content: 24 + 2 padding + 1 border on each side
	testing.expect_value(t, box.width, 24 + 6)
	testing.expect_value(t, box.height, 20 + 6)
	// the text "text" flows next to it
	text, _ := find_run(l, "text")
	testing.expect_value(t, text.x, 8 + 30)
	// one line of text: the body ends at 8 + 20 + 8 margin; the float (34) is lower
	testing.expect_value(t, l.height, 36)
}

@(test)
test_page_grows_with_float :: proc(t: ^testing.T) {
	doc, l := build_floats(t, `<img src="i.png" width="20" height="100" style="float: left">x`)
	defer dom.destroy(doc)
	defer destroy(l)
	// the float reaches below the body: the page must be scrollable that far
	testing.expect_value(t, l.height, 8 + 100)
}

@(test)
test_float_inside_table_cell_stays_inside :: proc(t: ^testing.T) {
	doc, l := build_floats(t, `<table><tr><td><img src="i.png" width="20" height="80" style="float: left">x</td></tr></table><p style="margin: 0">after</p>`)
	defer dom.destroy(doc)
	defer destroy(l)

	// the cell grows with its float, so "after" comes below the table, at full width
	after, _ := find_run(l, "after")
	testing.expect_value(t, after.x, 8)
	testing.expect(t, after.y > 80, "the table is as high as the float in its cell")
}

@(private = "file")
find_run :: proc(l: ^Layout, text: string) -> (Text_Run, bool) {
	for run in l.runs {
		if run.text == text {
			return run, true
		}
	}
	return {}, false
}
