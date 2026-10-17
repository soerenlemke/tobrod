package layout

import "core:testing"
import "../dom"

// body content: x 8..408 (400 wide), 8px per character at 16px

@(private = "file")
build_flex :: proc(t: ^testing.T, html: string) -> (doc: ^dom.Document, l: ^Layout) {
	err: Maybe(dom.Parse_Error)
	doc, err = dom.parse(html)
	if e, ok := err.?; ok {
		testing.fail_now(t, e.message)
	}
	return doc, build(doc, {416, 600}, fake_measure)
}

@(private = "file")
run_x :: proc(l: ^Layout, text: string) -> f32 {
	for run in l.runs {
		if run.text == text {
			return run.x
		}
	}
	return -1
}

@(private = "file")
run_y :: proc(l: ^Layout, text: string) -> f32 {
	for run in l.runs {
		if run.text == text {
			return run.y
		}
	}
	return -1
}

@(test)
test_flex_row :: proc(t: ^testing.T) {
	doc, l := build_flex(t, `<div style="display: flex"><div>aa</div><div>bbbb</div><span>c</span> loose</div>`)
	defer dom.destroy(doc)
	defer destroy(l)
	// side by side at their content width; loose text is an item of its own
	testing.expect_value(t, run_x(l, "aa"), 8)
	testing.expect_value(t, run_x(l, "bbbb"), 8 + 16)
	testing.expect_value(t, run_x(l, "c"), 8 + 16 + 32)
	testing.expect_value(t, run_x(l, "loose"), 8 + 16 + 32 + 8)
	testing.expect_value(t, run_y(l, "bbbb"), run_y(l, "aa"))
}

@(test)
test_flex_justify_and_gap :: proc(t: ^testing.T) {
	doc, l := build_flex(t, `<div style="display: flex; justify-content: space-between"><span>aa</span><span>bb</span><span>cc</span></div>
		<div style="display: flex; justify-content: center; gap: 10px"><span>dd</span><span>ee</span></div>`)
	defer dom.destroy(doc)
	defer destroy(l)
	// 400 - 3 * 16 = 352 left, 176 between the items
	testing.expect_value(t, run_x(l, "aa"), 8)
	testing.expect_value(t, run_x(l, "bb"), 8 + 16 + 176)
	testing.expect_value(t, run_x(l, "cc"), 408 - 16)
	// centered with a gap: 16 + 10 + 16 = 42 wide, (400 - 42) / 2 = 179 offset
	testing.expect_value(t, run_x(l, "dd"), 8 + 179)
	testing.expect_value(t, run_x(l, "ee"), 8 + 179 + 16 + 10)
}

@(test)
test_flex_grow_and_shrink :: proc(t: ^testing.T) {
	doc, l := build_flex(t, `<div style="display: flex"><div style="flex: 1; background: red">a</div><div style="flex: 1; background: blue">b</div></div>
		<div style="display: flex"><div style="width: 300px; background: red">c</div><div style="width: 300px; background: blue">d</div></div>`)
	defer dom.destroy(doc)
	defer destroy(l)
	testing.expect_value(t, len(l.boxes), 4)
	if len(l.boxes) != 4 do return
	// flex: 1 (basis 0): both get half of the 400px
	testing.expect_value(t, l.boxes[0].width, 200)
	testing.expect_value(t, l.boxes[1].x, 8 + 200)
	// 600px in 400px: both shrink by 100 (same shrink factor and base size)
	testing.expect_value(t, l.boxes[2].width, 200)
	testing.expect_value(t, l.boxes[3].width, 200)
}

@(test)
test_flex_wrap_and_align :: proc(t: ^testing.T) {
	doc, l := build_flex(t, `<div style="display: flex; flex-wrap: wrap; align-items: center">
		<div style="width: 150px">a<br>a</div><div style="width: 150px">b</div><div style="width: 150px">c</div></div>`)
	defer dom.destroy(doc)
	defer destroy(l)
	// two items fit into 400px, the third wraps to the next line
	testing.expect_value(t, run_x(l, "c"), 8)
	testing.expect(t, run_y(l, "c") > run_y(l, "b"), "c on the second line")
	// b (one line) is centered next to a (two lines): 10px lower than a's first line
	testing.expect_value(t, run_y(l, "b"), run_y(l, "a") + 10)
}

@(test)
test_flex_column :: proc(t: ^testing.T) {
	doc, l := build_flex(t, `<div style="display: flex; flex-direction: column; gap: 4px; align-items: center"><span>aa</span><span>bbbb</span></div>`)
	defer dom.destroy(doc)
	defer destroy(l)
	// one below the other with the gap, centered horizontally
	testing.expect_value(t, run_y(l, "bbbb"), run_y(l, "aa") + 20 + 4)
	testing.expect_value(t, run_x(l, "aa"), 8 + (400 - 16) / 2)
	testing.expect_value(t, run_x(l, "bbbb"), 8 + (400 - 32) / 2)
}

@(test)
test_flex_in_float_measures_its_items :: proc(t: ^testing.T) {
	// the float is as wide as the flex items, not as the "infinite" trial width
	doc, l := build_flex(t, `<div style="float: right; border: 1px solid black"><div style="display: flex; gap: 8px"><span>aa</span><span>bb</span></div></div>`)
	defer dom.destroy(doc)
	defer destroy(l)
	if len(l.boxes) != 1 do return
	testing.expect_value(t, l.boxes[0].width, 16 + 8 + 16 + 2)
	testing.expect_value(t, l.boxes[0].x, 408 - 42)
}
