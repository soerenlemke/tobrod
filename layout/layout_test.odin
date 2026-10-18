package layout

import "core:fmt"
import "core:strings"
import "core:testing"
import "core:unicode/utf8"
import "../dom"

// Every character is half as wide as the font size: exact numbers, no window needed.
fake_measure :: proc(text: string, font_size: f32, bold: bool) -> f32 {
	return f32(utf8.rune_count_in_string(text)) * font_size * 0.5
}

@(private = "file")
build_html :: proc(t: ^testing.T, html: string, width: f32) -> (doc: ^dom.Document, l: ^Layout) {
	err: Maybe(dom.Parse_Error)
	doc, err = dom.parse(html)
	if e, ok := err.?; ok {
		testing.fail_now(t, e.message)
	}
	return doc, build(doc, {width, 600}, fake_measure)
}

// "text@x,y size bold" per run, one per line, for compact expectations.
@(private = "file")
runs_to_string :: proc(l: ^Layout) -> string {
	b := strings.builder_make(context.temp_allocator)
	for run in l.runs {
		fmt.sbprintf(&b, "%s@%.6g,%.6g %v%s\n", run.text, run.x, run.y, run.font_size, " bold" if run.bold else "")
	}
	return strings.to_string(b)
}

@(test)
test_paragraph_wraps :: proc(t: ^testing.T) {
	// 16px font -> 8px per char; width 116 leaves 100px for text
	doc, l := build_html(t, "<p>aaaa bbbb cccc dddd</p>", 116)
	defer dom.destroy(doc)
	defer destroy(l)

	// "aaaa bbbb" = 72px fits, adding " cccc" = 112px doesn't.
	// The p margin (16) collapses with the page margin (8); the text sits
	// in the middle of its 20px line box -> y = 16 + 2.
	expected := "aaaa bbbb@8,18 16\ncccc dddd@8,38 16\n"
	testing.expect_value(t, runs_to_string(l), expected)
	// last line ends at 16 + 2*20 = 56, plus the p margin below
	testing.expect_value(t, l.height, 72)
}

@(test)
test_inline_styles :: proc(t: ^testing.T) {
	doc, l := build_html(t, `<p>a <b>bold</b> <span style="color: red">c</span></p>`, 800)
	defer dom.destroy(doc)
	defer destroy(l)

	testing.expect_value(t, len(l.runs), 3)
	if len(l.runs) != 3 do return
	testing.expect_value(t, l.runs[0].text, "a")
	testing.expect_value(t, l.runs[1].text, "bold")
	testing.expect(t, l.runs[1].bold, "expected bold run")
	testing.expect_value(t, l.runs[1].x, 8 + 8 + 8) // "a" + space
	testing.expect_value(t, l.runs[2].color, dom.Color{255, 0, 0, 255})
	testing.expect_value(t, l.runs[2].y, l.runs[0].y)
}

@(test)
test_headings_and_margins :: proc(t: ^testing.T) {
	doc, l := build_html(t, "<h1>Title</h1><p>one</p><p>two</p>", 800)
	defer dom.destroy(doc)
	defer destroy(l)

	// h1: 32px bold, margin 0.67em = 21.44 (wins over the page margin)
	// line box 40, text 32 -> y = 21.44 + 4
	// between h1 and p the margins collapse: max(21.44, 16) -> p line at 21.44 + 40 + 21.44
	// between the two p: max(16, 16) = 16, not 32
	expected := "Title@8,25.44 32 bold\none@8,84.88 16\ntwo@8,120.88 16\n"
	testing.expect_value(t, runs_to_string(l), expected)
}

@(test)
test_lists :: proc(t: ^testing.T) {
	doc, l := build_html(t, "<ul><li>a</li></ul><ol><li>x</li><li>y</li></ol>", 800)
	defer dom.destroy(doc)
	defer destroy(l)

	// marker hangs left of the 40px indent: x = 48 - space(8) - marker width
	expected := "•@32,18 16\na@48,18 16\n1.@24,54 16\nx@48,54 16\n2.@24,74 16\ny@48,74 16\n"
	testing.expect_value(t, runs_to_string(l), expected)
}

@(test)
test_hidden_br_and_pre :: proc(t: ^testing.T) {
	doc, l := build_html(t, "<div>a<br>b<span hidden>no</span></div><pre>x  y\n\nz</pre>", 800)
	defer dom.destroy(doc)
	defer destroy(l)

	// pre keeps the two spaces (x moves 16px) and the empty line;
	// the spaces split the run because the exact spacing must stay
	expected := "a@8,10 16\nb@8,30 16\nx@8,66 16\ny@32,66 16\nz@8,106 16\n"
	testing.expect_value(t, runs_to_string(l), expected)
}

@(test)
test_plain_text :: proc(t: ^testing.T) {
	doc, err := dom.from_plain_text("line one\nline two")
	if e, ok := err.?; ok {
		testing.fail_now(t, e.message)
	}
	defer dom.destroy(doc)
	l := build(doc, {800, 600}, fake_measure)
	defer destroy(l)

	// separate runs per word in pre text (spaces are kept exactly)
	expected := "line@8,18 16\none@48,18 16\nline@8,38 16\ntwo@48,38 16\n"
	testing.expect_value(t, runs_to_string(l), expected)
}

@(test)
test_display_from_css :: proc(t: ^testing.T) {
	doc, l := build_html(t, `<html><head><style>
		.ad { display: none }
		span.box { display: block }
		ul.inline li { display: inline }
	</style><title>not shown</title></head><body>
		<p>Text<span class="ad">AD</span> more</p>
		<p>a<span class="box">boxed</span>b</p>
		<ul class="inline"><li>x</li> <li>y</li></ul>
		<script>not shown</script>
	</body></html>`, 800)
	defer dom.destroy(doc)
	defer destroy(l)

	// the span block splits the line; inline list items have no markers
	texts := make([dynamic]string, context.temp_allocator)
	for run in l.runs {
		append(&texts, run.text)
	}
	expected := []string{"Text more", "a", "boxed", "b", "x y"}
	testing.expect_value(t, len(texts), len(expected))
	for text, i in expected {
		if i < len(texts) {
			testing.expect_value(t, texts[i], text)
		}
	}
}

@(test)
test_links :: proc(t: ^testing.T) {
	doc, l := build_html(t, `<p>go <a href="next.html">to <b>next</b></a> page</p>`, 800)
	defer dom.destroy(doc)
	defer destroy(l)

	// "go" | "to" | "next" (bold) | "page": runs split at link and style borders
	testing.expect_value(t, len(l.runs), 4)
	if len(l.runs) != 4 do return
	testing.expect_value(t, l.runs[0].link, "")
	testing.expect_value(t, l.runs[1].link, "next.html")
	testing.expect_value(t, l.runs[2].link, "next.html")
	testing.expect_value(t, l.runs[3].link, "")
	testing.expect_value(t, l.runs[1].width, 16) // "to" = 2 chars * 8px

	// hit test inside "to", inside the bold "next" and outside the link
	link, ok := link_at(l, l.runs[1].x + 1, l.runs[1].y + 1)
	testing.expect(t, ok && link == "next.html", "expected hit on 'to'")
	link, ok = link_at(l, l.runs[2].x + l.runs[2].width - 1, l.runs[2].y + 8)
	testing.expect(t, ok && link == "next.html", "expected hit on 'next'")
	_, ok = link_at(l, l.runs[0].x + 1, l.runs[0].y + 1)
	testing.expect(t, !ok, "expected no link on 'go'")
	_, ok = link_at(l, l.runs[1].x + 1, l.runs[1].y + 100)
	testing.expect(t, !ok, "expected no link below the line")
}

@(test)
test_box_model :: proc(t: ^testing.T) {
	// window 400 wide, body content 384 (8px margin each side)
	doc, l := build_html(t, `<html><head><style>
		body { background: #eee }
		.card { max-width: 200px; margin: 0 auto; padding: 10px 20px; background: #fff }
		.card p { margin: 5px 0 }
	</style></head><body><div class="card"><p>hi</p></div></body></html>`, 400)
	defer dom.destroy(doc)
	defer destroy(l)

	// body background becomes the page background ("canvas")
	testing.expect_value(t, l.background, dom.Color{0xee, 0xee, 0xee, 255})

	// card: 200 wide content + 2*20 padding = 240, centered in 384 -> x = 8 + 72
	testing.expect_value(t, len(l.boxes), 1)
	if len(l.boxes) != 1 do return
	card := l.boxes[0]
	testing.expect_value(t, card.x, 80)
	testing.expect_value(t, card.width, 240)
	// the body margin (8) is applied at the card's padding: card top = 8;
	// the p margin can't collapse through the padding, so text sits at
	// 8 + 10 padding + 5 margin + 2 (centered in its 20px line box)
	testing.expect_value(t, card.y, 8)
	testing.expect_value(t, l.runs[0].x, 100) // 80 + 20 padding
	testing.expect_value(t, l.runs[0].y, 25)
	// height: 10 padding + 5 + 20 line + 5 + 10 padding
	testing.expect_value(t, card.height, 50)
}

@(test)
test_margins_collapse_through_parent :: proc(t: ^testing.T) {
	// without padding, the p margin collapses with the div and body margins:
	// the div background starts where the text starts, not at the body margin
	doc, l := build_html(t, `<div style="background: red"><p style="margin: 30px 0">x</p></div>`, 400)
	defer dom.destroy(doc)
	defer destroy(l)

	if len(l.boxes) != 1 do return
	testing.expect_value(t, l.boxes[0].y, 30)
	testing.expect_value(t, l.boxes[0].height, 20) // only the line, the p margins stay outside
	testing.expect_value(t, l.runs[0].y, 32)
	testing.expect_value(t, l.height, 30 + 20 + 30)
}

@(test)
test_percent_width :: proc(t: ^testing.T) {
	doc, l := build_html(t, `<div style="width: 50%; margin-left: auto">right half</div>`, 416)
	defer dom.destroy(doc)
	defer destroy(l)

	// content 400 wide -> div 200 wide, auto left margin pushes it right
	testing.expect_value(t, l.runs[0].x, 8 + 200)
}

@(test)
test_text_align :: proc(t: ^testing.T) {
	// body content: 8..408 (400 wide); "ab" = 16px
	doc, l := build_html(t, `<p style="text-align: center">ab</p><p style="text-align: right">ab</p><ul style="text-align: right"><li>ab</li></ul>`, 416)
	defer dom.destroy(doc)
	defer destroy(l)

	testing.expect_value(t, l.runs[0].x, 8 + (400 - 16) / 2)
	testing.expect_value(t, l.runs[1].x, 408 - 16)
	// the list marker stays left of the content, only the text moves
	testing.expect_value(t, l.runs[2].text, "•")
	testing.expect_value(t, l.runs[2].x, 32)
	testing.expect_value(t, l.runs[3].x, 408 - 16)
}

@(test)
test_borders :: proc(t: ^testing.T) {
	doc, l := build_html(t, `<div style="border: 2px solid red; padding: 3px"><p style="margin: 10px 0">x</p></div><hr>`, 416)
	defer dom.destroy(doc)
	defer destroy(l)

	testing.expect_value(t, len(l.boxes), 2)
	if len(l.boxes) != 2 do return
	div := l.boxes[0]
	// the border adds to the box like padding: 400 = 2 + 3 + content + 3 + 2
	testing.expect_value(t, div.x, 8)
	testing.expect_value(t, div.width, 400)
	testing.expect_value(t, div.border[.Top], 2)
	testing.expect_value(t, div.border_color[.Left], dom.Color{255, 0, 0, 255})
	// border + padding stop margin collapsing: the p margin stays inside
	testing.expect_value(t, div.y, 8)
	testing.expect_value(t, l.runs[0].x, 8 + 5)
	testing.expect_value(t, l.runs[0].y, 8 + 5 + 10 + 2)
	testing.expect_value(t, div.height, 5 + 10 + 20 + 10 + 5)

	// hr: an empty box with a 1px grey border on all sides -> 2px high line
	hr := l.boxes[1]
	testing.expect_value(t, hr.height, 2)
	testing.expect_value(t, hr.width, 400)
	testing.expect_value(t, hr.border_color[.Top], dom.Color{128, 128, 128, 255})
}

@(test)
test_vh_padding :: proc(t: ^testing.T) {
	// viewport height 600 in the tests: 10vh = 60px
	doc, l := build_html(t, `<body style="margin: 0; padding-top: 10vh">x</body>`, 400)
	defer dom.destroy(doc)
	defer destroy(l)
	testing.expect_value(t, l.runs[0].y, 60 + 2)
}

@(test)
test_image_sizes :: proc(t: ^testing.T) {
	doc, err := dom.parse(`<p>
		<img src="a.png" width="100" height="50">
		<img src="b.png" style="width: 20px">
		<img src="loaded.png" width="40">
		<img src="loaded.png">
		<img src="big.png" style="max-width: 100%">
	</p>`)
	if e, ok := err.?; ok {
		testing.fail_now(t, e.message)
	}
	defer dom.destroy(doc)

	sizes := make(Image_Sizes)
	defer delete(sizes)
	sizes["loaded.png"] = {80, 60}
	sizes["big.png"] = {2000, 1000}

	l := build(doc, {416, 600}, fake_measure, sizes)
	defer destroy(l)

	testing.expect_value(t, len(l.images), 5)
	if len(l.images) != 5 do return
	expect_size :: proc(t: ^testing.T, image: Image_Item, w, h: f32, loc := #caller_location) {
		testing.expectf(t, image.width == w && image.height == h, "%s: got %vx%v, want %vx%v", image.src, image.width, image.height, w, h, loc = loc)
	}
	expect_size(t, l.images[0], 100, 50)   // attributes
	expect_size(t, l.images[1], 20, 16)    // CSS width, height unknown -> placeholder height
	expect_size(t, l.images[2], 40, 30)    // width given, height from the aspect ratio
	expect_size(t, l.images[3], 80, 60)    // natural size
	expect_size(t, l.images[4], 400, 200)  // max-width: 100% of the 400px body, proportional
}

@(test)
test_images_in_lines :: proc(t: ^testing.T) {
	// body content 8..408. "ab" is 16px, the image 100x50
	doc, l := build_html(t, `<p>ab <a href="x.html"><img src="i.png" width="100" height="50"></a> ab</p>`, 416)
	defer dom.destroy(doc)
	defer destroy(l)

	if len(l.images) != 1 || len(l.runs) != 2 do return
	image := l.images[0]
	// placed after "ab" and a space, the line is 50px high, everything on its bottom
	testing.expect_value(t, image.x, 8 + 16 + 8)
	testing.expect_value(t, image.y, 16)
	testing.expect_value(t, l.runs[0].y, 16 + 50 - 20 + 2)
	testing.expect_value(t, l.runs[1].x, 8 + 16 + 8 + 100 + 8)
	testing.expect_value(t, l.height, 16 + 50 + 16)

	// the image belongs to the link
	link, ok := link_at(l, image.x + 50, image.y + 25)
	testing.expect(t, ok && link == "x.html", "expected the image to be a link")
}

@(test)
test_image_wraps :: proc(t: ^testing.T) {
	// a 300px image doesn't fit next to the 300px of text in a 400px line
	doc, l := build_html(t, `<p>aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa <img src="i.png" width="300" height="10"></p>`, 416)
	defer dom.destroy(doc)
	defer destroy(l)
	if len(l.images) != 1 do return
	testing.expect_value(t, l.images[0].x, 8)
	testing.expect(t, l.images[0].y > l.runs[0].y, "image on the next line")
}

@(test)
test_visibility_and_out_of_flow :: proc(t: ^testing.T) {
	doc, l := build_html(t, `<p>a <span style="visibility: hidden">hidden</span> b</p><div style="position: absolute">gone</div><p>c</p>`, 800)
	defer dom.destroy(doc)
	defer destroy(l)

	texts := make([dynamic]string, context.temp_allocator)
	for run in l.runs {
		append(&texts, run.text)
	}
	// "hidden" is not drawn but still takes its space: "b" stays where it was
	testing.expect_value(t, len(texts), 4)
	if len(texts) == 4 {
		testing.expect_value(t, texts[0], "a")
		testing.expect_value(t, texts[1], "b")
		testing.expect_value(t, l.runs[1].x, 8 + 8 + 8 + 48 + 8) // a, space, hidden (6 chars), space
		testing.expect_value(t, texts[2], "c")
		// the absolute div takes no space: "c" follows the first p directly,
		// and "gone" is drawn at its static position, on top of "c"
		testing.expect_value(t, l.runs[2].y, 18 + 20 + 16)
		testing.expect_value(t, texts[3], "gone")
		testing.expect_value(t, l.runs[3].y, l.runs[2].y)
	}
}

@(test)
test_list_markers :: proc(t: ^testing.T) {
	doc, l := build_html(t, `<ul style="list-style: none"><li>none</li></ul><ul style="list-style-type: square"><li><div><a href="x">nested</a></div></li></ul>`, 800)
	defer dom.destroy(doc)
	defer destroy(l)

	// no marker for list-style: none; the square marker sits on the first line
	// of its li even though the text is inside a nested block
	testing.expect_value(t, len(l.runs), 3)
	if len(l.runs) != 3 do return
	testing.expect_value(t, l.runs[0].text, "none")
	testing.expect_value(t, l.runs[1].text, "▪")
	testing.expect_value(t, l.runs[2].text, "nested")
	testing.expect_value(t, l.runs[1].y, l.runs[2].y)
}

@(test)
test_replaced_elements :: proc(t: ^testing.T) {
	doc, err := dom.parse(`<p><video poster="p.jpg" width="250" height="159"><source src="v.webm"></video><iframe src="x"></iframe><video></video></p>`)
	if e, ok := err.?; ok {
		testing.fail_now(t, e.message)
	}
	defer dom.destroy(doc)
	l := build(doc, {1000, 600}, fake_measure)
	defer destroy(l)

	testing.expect_value(t, len(l.images), 3)
	if len(l.images) != 3 do return
	// video: its size attributes, its poster as the picture
	testing.expect_value(t, l.images[0].src, "p.jpg")
	testing.expect_value(t, l.images[0].width, 250)
	testing.expect_value(t, l.images[0].height, 159)
	// without sizes: the 300x150 default of replaced elements
	testing.expect_value(t, l.images[1].width, 300)
	testing.expect_value(t, l.images[2].height, 150)
	// the <source> inside the video is not laid out as text
	testing.expect_value(t, len(l.runs), 0)
}

@(test)
test_block_height :: proc(t: ^testing.T) {
	cases := []struct {
		style:  string,
		height: f32, // of the red box; one line of text is 20 high
	} {
		{"height: 100px", 100},
		{"height: 10px", 10},   // the text overflows
		{"height: 50%", 20},    // % of an auto height: like auto
		{"height: 10vh", 60},   // viewport 600 high
		{"height: 2em", 32},
		{"min-height: 50px", 50},
		{"min-height: 5px", 20},
		{"max-height: 10px", 10},
		{"max-height: 10px; min-height: 30px", 30}, // min wins
		{"height: 100px; max-height: 40px", 40},
	}
	for c in cases {
		html := fmt.tprintf(`<body style="margin: 0"><div style="background: red; %s">x</div><p style="margin: 0">after</p></body>`, c.style)
		doc, l := build_html(t, html, 400)
		defer dom.destroy(doc)
		defer destroy(l)

		if !testing.expectf(t, len(l.boxes) == 1 && len(l.runs) == 2, "%s: %d boxes, %d runs", c.style, len(l.boxes), len(l.runs)) {
			continue
		}
		testing.expectf(t, l.boxes[0].height == c.height, "%s: box height %v, want %v", c.style, l.boxes[0].height, c.height)
		// the next block starts below the box, even if the text overflows it
		testing.expectf(t, l.runs[1].y == c.height + 2, "%s: next line at %v, want %v", c.style, l.runs[1].y, c.height + 2)
	}
}

@(test)
test_block_height_margins :: proc(t: ^testing.T) {
	// an empty block with a height takes room; the bottom margin of the last
	// child stays inside a box with a height and doesn't collapse with it
	doc, l := build_html(t, `<body style="margin: 0">
		<div style="height: 40px; margin-bottom: 10px; background: red"></div>
		<div style="height: 50px; margin-bottom: 10px; background: blue"><p style="margin: 0 0 30px">x</p></div>
		<p style="margin: 0">after</p></body>`, 400)
	defer dom.destroy(doc)
	defer destroy(l)

	if len(l.boxes) != 2 do return
	testing.expect_value(t, l.boxes[0].y, 0)
	testing.expect_value(t, l.boxes[0].height, 40)
	testing.expect_value(t, l.boxes[1].y, 50)
	testing.expect_value(t, l.boxes[1].height, 50)
	testing.expect_value(t, l.runs[1].y, 50 + 50 + 10 + 2)
}

@(test)
test_position_relative_block :: proc(t: ^testing.T) {
	// the box and its text move, the next block stays where it would be
	doc, l := build_html(t, `<body style="margin: 0">
		<div style="position: relative; top: 10px; left: 30px; background: red">a</div>
		<div style="position: relative; bottom: 5px; right: 20px">b</div>
		<p style="margin: 0">c</p></body>`, 400)
	defer dom.destroy(doc)
	defer destroy(l)

	if len(l.boxes) != 1 || len(l.runs) != 3 do return
	testing.expect_value(t, l.boxes[0].x, 30)
	testing.expect_value(t, l.boxes[0].y, 10)
	testing.expect_value(t, runs_to_string(l), "a@30,12 16\nb@-20,17 16\nc@0,42 16\n")
	testing.expect_value(t, l.height, 60)
}

@(test)
test_position_relative_inline :: proc(t: ^testing.T) {
	// "x " is 16 wide, "up " 24; the span moves, the text after it stays
	doc, l := build_html(t, `<body style="margin: 0">x <span style="position: relative; top: -4px; left: 2px">up</span> y</body>`, 400)
	defer dom.destroy(doc)
	defer destroy(l)

	testing.expect_value(t, runs_to_string(l), "x@0,2 16\nup@18,-2 16\ny@40,2 16\n")
}

@(test)
test_position_relative_ignores_others :: proc(t: ^testing.T) {
	// static and sticky elements are not moved, % of an unknown height is 0,
	// left wins over right and top over bottom
	doc, l := build_html(t, `<body style="margin: 0">
		<div style="top: 10px; left: 10px">a</div>
		<div style="position: sticky; top: 10px">b</div>
		<div style="position: relative; top: 50%; left: 10%">c</div>
		<div style="position: relative; inset: 1px 2px 3px 4px">d</div></body>`, 400)
	defer dom.destroy(doc)
	defer destroy(l)

	testing.expect_value(t, runs_to_string(l), "a@0,2 16\nb@0,22 16\nc@40,42 16\nd@4,63 16\n")
}

@(test)
test_positioned_boxes_drawn_last :: proc(t: ^testing.T) {
	doc, l := build_html(t, `<body style="margin: 0">
		<div style="position: relative; top: 10px; background: red"><div style="position: relative; background: green; left: 1px">a</div></div>
		<div style="background: blue">b</div></body>`, 400)
	defer dom.destroy(doc)
	defer destroy(l)

	if len(l.boxes) != 3 do return
	testing.expect_value(t, l.boxes[0].color, dom.Color{0, 0, 255, 255})
	testing.expect_value(t, l.boxes[1].color, dom.Color{255, 0, 0, 255})
	testing.expect_value(t, l.boxes[2].color, dom.Color{0, 128, 0, 255})
}

@(test)
test_position_absolute_containing_block :: proc(t: ^testing.T) {
	// the padding box of the relative div: x 2..398, y 52..172 (100 + 2 * 10 padding)
	doc, l := build_html(t, `<body style="margin: 0">
		<div style="position: relative; margin-top: 50px; padding: 10px; border: 2px solid; height: 100px">
			<div style="position: absolute; top: 5px; left: 7px">a</div>
			<div style="position: absolute; right: 0; bottom: 0; width: 40px">b</div>
			in flow
		</div></body>`, 400)
	defer dom.destroy(doc)
	defer destroy(l)

	// "in flow" is laid out as if the absolute elements were not there
	testing.expect_value(t, runs_to_string(l), "in flow@12,64 16\na@9,59 16\nb@358,154 16\n")
}

@(test)
test_position_absolute_initial_containing_block :: proc(t: ^testing.T) {
	// without a positioned ancestor: the first screen of the page (400 x 600)
	doc, l := build_html(t, `<body>
		<div style="position: absolute; bottom: 0; background: red">abcd</div>
		<div style="position: absolute; left: 10px; right: 20px; top: 0; bottom: 0; background: blue"></div>
		<div style="position: absolute; top: 1000px">far down</div></body>`, 400)
	defer dom.destroy(doc)
	defer destroy(l)

	if len(l.boxes) != 2 do return
	// shrink-to-fit: as wide as "abcd", at the bottom of the screen
	red := l.boxes[0]
	testing.expect_value(t, [4]f32{red.x, red.y, red.width, red.height}, [4]f32{8, 580, 32, 20})
	// stretched between left/right and top/bottom
	blue := l.boxes[1]
	testing.expect_value(t, [4]f32{blue.x, blue.y, blue.width, blue.height}, [4]f32{10, 0, 370, 600})
	// the page grows with absolute elements
	testing.expect_value(t, l.height, 1020)
}

@(test)
test_position_absolute_static_position :: proc(t: ^testing.T) {
	// auto offsets: where the element would be in the flow; an inline one
	// stays in its line, the text after it doesn't make room
	doc, l := build_html(t, `<body style="margin: 0">
		<p style="margin: 0">x <span style="position: absolute; top: auto">abs</span>y</p>
		<div style="position: absolute; left: 100px">block</div><p style="margin: 0">z</p></body>`, 400)
	defer dom.destroy(doc)
	defer destroy(l)

	testing.expect_value(t, runs_to_string(l), "x y@0,2 16\nz@0,22 16\nabs@16,2 16\nblock@100,22 16\n")
}

@(test)
test_position_absolute_drawn_on_top :: proc(t: ^testing.T) {
	doc, l := build_html(t, `<body style="margin: 0">
		<div style="position: absolute; top: 0; background: red">a</div>
		<div style="background: blue">b</div></body>`, 400)
	defer dom.destroy(doc)
	defer destroy(l)

	if len(l.boxes) != 2 do return
	testing.expect_value(t, l.boxes[0].color, dom.Color{0, 0, 255, 255})
	testing.expect_value(t, l.boxes[1].color, dom.Color{255, 0, 0, 255})
}

@(test)
test_position_absolute_clipped_away :: proc(t: ^testing.T) {
	// the usual "visually hidden" pattern; a clip rect with an area is ignored
	doc, l := build_html(t, `<body>
		<a style="position: absolute; clip: rect(1px, 1px, 1px, 1px); width: 1px; overflow: hidden" href="#c">Skip to content</a>
		<div style="position: absolute; clip: rect(0 auto auto 0)">shown</div></body>`, 400)
	defer dom.destroy(doc)
	defer destroy(l)

	testing.expect_value(t, len(l.runs), 1)
	if len(l.runs) == 1 {
		testing.expect_value(t, l.runs[0].text, "shown")
	}
}

@(test)
test_position_absolute_percent_height :: proc(t: ^testing.T) {
	// a cover image: absolute, inset 0, 100% x 100% of the relative card
	doc, l := build_html(t, `<body style="margin: 0">
		<div style="position: relative; height: 200px; width: 300px">
			<img src="cover.png" style="position: absolute; inset: 0; width: 100%; height: 100%">
		</div></body>`, 400)
	defer dom.destroy(doc)
	defer destroy(l)

	if len(l.images) != 1 do return
	image := l.images[0]
	testing.expect_value(t, [4]f32{image.x, image.y, image.width, image.height}, [4]f32{0, 0, 300, 200})
}

@(test)
test_position_fixed_layer :: proc(t: ^testing.T) {
	// a header bar fixed to the top: in its own layer, the page doesn't make
	// room for it and doesn't grow
	doc, l := build_html(t, `<body style="margin: 0">
		<div style="position: fixed; top: 0; left: 0; right: 0; height: 30px; background: red">bar</div>
		<div style="position: relative; margin-top: 100px">
			<span style="position: fixed; bottom: 10px; right: 10px">ok</span>
		</div>
		<p style="margin: 0">text</p></body>`, 400)
	defer dom.destroy(doc)
	defer destroy(l)

	testing.expect_value(t, len(l.boxes), 0)
	testing.expect_value(t, runs_to_string(l), "text@0,102 16\n")
	testing.expect_value(t, l.height, 120)

	if len(l.fixed.boxes) != 1 || len(l.fixed.runs) != 2 do return
	bar := l.fixed.boxes[0]
	testing.expect_value(t, [4]f32{bar.x, bar.y, bar.width, bar.height}, [4]f32{0, 0, 400, 30})
	testing.expect_value(t, l.fixed.runs[0].text, "bar")
	// against the viewport (400 x 600), not the relative div
	ok := l.fixed.runs[1]
	testing.expect_value(t, [2]f32{ok.x, ok.y}, [2]f32{400 - 10 - 16, 600 - 10 - 20 + 2})
}

@(test)
test_position_fixed_links :: proc(t: ^testing.T) {
	// a fixed link stays clickable at the same place in the window, wherever
	// the page is scrolled to; it covers the page link below it
	doc, l := build_html(t, `<body style="margin: 0">
		<a href="top" style="position: fixed; top: 0; left: 0">fixed</a>
		<div style="height: 2000px"><a href="page">page</a></div></body>`, 400)
	defer dom.destroy(doc)
	defer destroy(l)

	link, ok := link_at(l, 5, 5)
	testing.expect(t, ok && link == "top", "fixed link over the page link")
	link, ok = link_at(l, 5, 1005, 1000)
	testing.expect(t, ok && link == "top", "fixed link after scrolling")
	link, ok = link_at(l, 5, 5 + 1000, 0)
	testing.expect(t, !ok, "nothing on the page there")
}

@(private = "file")
expect_clip :: proc(t: ^testing.T, l: ^Layout, clip: Clip, want: [4]f32, loc := #caller_location) {
	r, ok := clip_rect(l, clip)
	testing.expectf(t, ok && [4]f32{r.x, r.y, r.width, r.height} == want, "clip %v: got %v (%v), want %v", clip, r, ok, want, loc = loc)
}

@(test)
test_overflow_hidden :: proc(t: ^testing.T) {
	// the border box is 112 x 32 at 0,0; the clip is its padding box
	doc, l := build_html(t, `<body style="margin: 0">
		<div style="overflow: hidden; width: 100px; height: 20px; padding: 5px; border: 1px solid; background: red">
			<p style="margin: 0">a</p><div style="background: blue">b</div>
		</div><p style="margin: 0">after</p></body>`, 400)
	defer dom.destroy(doc)
	defer destroy(l)

	if len(l.boxes) != 2 || len(l.runs) != 3 do return
	testing.expect_value(t, l.boxes[0].clip, Clip(0)) // its own box is not clipped
	testing.expect_value(t, l.boxes[1].clip, Clip(1))
	testing.expect_value(t, l.runs[0].clip, Clip(1))
	testing.expect_value(t, l.runs[1].clip, Clip(1)) // "b" sticks out below, it is cut off
	testing.expect_value(t, l.runs[2].clip, Clip(0))
	expect_clip(t, l, 1, {1, 1, 110, 30})
}

@(test)
test_overflow_nested_and_axes :: proc(t: ^testing.T) {
	doc, l := build_html(t, `<body style="margin: 0">
		<div style="overflow: hidden; width: 100px">
			<div style="overflow: hidden; margin-left: 50px; width: 200px">x</div>
		</div>
		<div style="overflow-x: hidden">y: visible becomes auto, so both axes clip</div>
		<div style="overflow-x: clip">z: clip leaves the other axis visible</div></body>`, 400)
	defer dom.destroy(doc)
	defer destroy(l)

	if len(l.runs) != 3 do return
	// the inner clip is cut down to the outer one: x 50..100
	expect_clip(t, l, l.runs[0].clip, {50, 0, 50, 20})
	expect_clip(t, l, l.runs[1].clip, {0, 20, 400, 20})
	expect_clip(t, l, l.runs[2].clip, {0, -1e9, 400, 2e9})
}

@(test)
test_overflow_absolute_and_relative :: proc(t: ^testing.T) {
	// an absolute child is only clipped if its containing block is inside;
	// a relative shift moves the clip along
	doc, l := build_html(t, `<body style="margin: 0">
		<div style="overflow: hidden; height: 10px"><span style="position: absolute; top: 50px">free</span></div>
		<div style="overflow: hidden; height: 10px; position: relative; left: 7px"><span style="position: absolute; top: 50px">cut</span></div>
	</body>`, 400)
	defer dom.destroy(doc)
	defer destroy(l)

	if len(l.runs) != 2 do return
	free, cut := l.runs[0], l.runs[1]
	if free.text != "free" {
		free, cut = cut, free
	}
	testing.expect_value(t, free.clip, Clip(0))
	expect_clip(t, l, cut.clip, {7, 10, 400, 10})
}

@(test)
test_overflow_links :: proc(t: ^testing.T) {
	// the second line of the link is cut off: clicking there hits nothing
	doc, l := build_html(t, `<body style="margin: 0"><div style="overflow: hidden; height: 20px; width: 40px">
		<a href="x">aaaa bbbb</a></div></body>`, 400)
	defer dom.destroy(doc)
	defer destroy(l)

	_, ok := link_at(l, 5, 10)
	testing.expect(t, ok, "visible part of the link")
	_, ok = link_at(l, 5, 30)
	testing.expect(t, !ok, "clipped part of the link")
}

@(private = "file")
box_rect :: proc(box: Box) -> [4]f32 {
	return {box.x, box.y, box.width, box.height}
}

@(test)
test_inline_background :: proc(t: ^testing.T) {
	// "a " is 16 wide; the padding makes room on both sides of "bc"; the box
	// covers the line box of the font (20) plus the vertical padding
	doc, l := build_html(t, `<body style="margin: 0">a <span style="background: red; padding: 2px 4px">bc</span> d</body>`, 400)
	defer dom.destroy(doc)
	defer destroy(l)

	testing.expect_value(t, runs_to_string(l), "a@0,2 16\nbc@20,2 16\nd@48,2 16\n")
	if len(l.boxes) != 1 do return
	testing.expect_value(t, box_rect(l.boxes[0]), [4]f32{16, -2, 24, 24})
	testing.expect_value(t, l.boxes[0].color, dom.Color{255, 0, 0, 255})
	testing.expect_value(t, l.height, 20) // padding doesn't make the line higher
}

@(test)
test_inline_background_wraps :: proc(t: ^testing.T) {
	// one box per line; the left border only on the first, the right one
	// only on the last
	doc, l := build_html(t, `<body style="margin: 0"><span style="background: red; border: 1px solid">aaaa bbbb</span></body>`, 60)
	defer dom.destroy(doc)
	defer destroy(l)

	testing.expect_value(t, runs_to_string(l), "aaaa@1,2 16\nbbbb@0,22 16\n")
	if len(l.boxes) != 2 do return
	first, second := l.boxes[0], l.boxes[1]
	testing.expect_value(t, box_rect(first), [4]f32{0, -1, 33, 22})
	testing.expect_value(t, first.border, [dom.Edge]f32{.Top = 1, .Right = 0, .Bottom = 1, .Left = 1})
	testing.expect_value(t, box_rect(second), [4]f32{0, 19, 33, 22})
	testing.expect_value(t, second.border, [dom.Edge]f32{.Top = 1, .Right = 1, .Bottom = 1, .Left = 0})
}

@(test)
test_inline_margins_and_markers :: proc(t: ^testing.T) {
	// a margin only makes room; the list marker is not part of the span's box
	doc, l := build_html(t, `<body style="margin: 0">x<span style="margin-left: 10px">y</span>z
		<ul style="margin: 0; padding-left: 40px"><li><span style="background: red">a</span></li></ul></body>`, 400)
	defer dom.destroy(doc)
	defer destroy(l)

	if len(l.runs) < 3 || len(l.boxes) != 1 do return
	testing.expect_value(t, l.runs[1].x, 18)
	testing.expect_value(t, l.runs[2].x, 26)
	testing.expect_value(t, l.boxes[0].x, 40)
	testing.expect_value(t, l.boxes[0].width, 8)
}

@(test)
test_text_decoration_runs :: proc(t: ^testing.T) {
	// a link becomes its own run with the underline; text around it has none
	doc, l := build_html(t, `<body style="margin: 0">a <a href="x">b c</a> d</body>`, 400)
	defer dom.destroy(doc)
	defer destroy(l)

	if len(l.runs) != 3 do return
	testing.expect_value(t, l.runs[0].decoration.lines, dom.Decoration_Lines{})
	testing.expect_value(t, l.runs[1].text, "b c")
	testing.expect_value(t, l.runs[1].decoration.lines, dom.Decoration_Lines{.Underline})
	testing.expect_value(t, l.runs[2].decoration.lines, dom.Decoration_Lines{})
}

@(test)
test_text_decoration_spaces :: proc(t: ^testing.T) {
	// the space inside the link is underlined with the next run, the one
	// before the link is not
	doc, l := build_html(t, `<body style="margin: 0">x <a href="y">a <b>b</b></a></body>`, 400)
	defer dom.destroy(doc)
	defer destroy(l)

	if len(l.runs) != 3 do return
	testing.expect_value(t, l.runs[1].decoration_lead, 0)
	testing.expect_value(t, l.runs[2].text, "b")
	testing.expect_value(t, l.runs[2].decoration_lead, 8)
}

@(test)
test_line_height_layout :: proc(t: ^testing.T) {
	// 30px lines: the 16px text sits in the middle of each
	doc, l := build_html(t, `<body style="margin: 0; line-height: 30px">aaaa bbbb</body>`, 40)
	defer dom.destroy(doc)
	defer destroy(l)

	testing.expect_value(t, runs_to_string(l), "aaaa@0,7 16\nbbbb@0,37 16\n")
	testing.expect_value(t, l.height, 60)
}

@(test)
test_line_height_inline_background :: proc(t: ^testing.T) {
	// a tall line doesn't make the background taller: it covers the font's
	// content area (20px) around the text
	doc, l := build_html(t, `<body style="margin: 0; line-height: 40px">a <span style="background: red">b</span></body>`, 400)
	defer dom.destroy(doc)
	defer destroy(l)

	if len(l.boxes) != 1 || len(l.runs) != 2 do return
	testing.expect_value(t, l.runs[1].y, 12)
	testing.expect_value(t, box_rect(l.boxes[0]), [4]f32{16, 10, 8, 20})
}

@(test)
test_inline_block_baseline :: proc(t: ^testing.T) {
	// shrink-to-fit: "bc" (16) + padding 2 x 4 = 24 wide; its text lines up
	// with the text around it, the bottom padding hangs below the line's text
	doc, l := build_html(t, `<body style="margin: 0">a <span style="display: inline-block; padding: 4px; background: red">bc</span> d</body>`, 400)
	defer dom.destroy(doc)
	defer destroy(l)

	testing.expect_value(t, runs_to_string(l), "bc@20,6 16\na@0,6 16\nd@48,6 16\n")
	if len(l.boxes) != 1 do return
	testing.expect_value(t, box_rect(l.boxes[0]), [4]f32{16, 0, 24, 28})
	testing.expect_value(t, l.height, 28)
}

@(test)
test_inline_block_wraps_and_width :: proc(t: ^testing.T) {
	// two 150px boxes don't fit next to each other in 200px
	doc, l := build_html(t, `<body style="margin: 0">
		<span style="display: inline-block; width: 150px; background: red">a</span>
		<span style="display: inline-block; width: 150px; background: blue">b</span></body>`, 200)
	defer dom.destroy(doc)
	defer destroy(l)

	if len(l.boxes) != 2 do return
	testing.expect_value(t, box_rect(l.boxes[0]), [4]f32{0, 0, 150, 20})
	testing.expect_value(t, box_rect(l.boxes[1]), [4]f32{0, 20, 150, 20})
}

@(test)
test_inline_flex_and_empty_block :: proc(t: ^testing.T) {
	// inline-flex: items side by side inside, the box in the line; an empty
	// inline block sits on the baseline with its bottom edge
	doc, l := build_html(t, `<body style="margin: 0">
		<span style="display: inline-flex; gap: 10px"><span>a</span><span>b</span></span>
		<span style="display: inline-block; width: 10px; height: 30px; background: red"></span>x</body>`, 400)
	defer dom.destroy(doc)
	defer destroy(l)

	testing.expect_value(t, runs_to_string(l), "a@0,12 16\nb@18,12 16\nx@44,12 16\n")
	if len(l.boxes) != 1 do return
	testing.expect_value(t, box_rect(l.boxes[0]), [4]f32{34, 0, 10, 30})
}

@(test)
test_box_sizing :: proc(t: ^testing.T) {
	// border-box: width and height include padding (10) and border (5)
	doc, l := build_html(t, `<body style="margin: 0">
		<div style="box-sizing: border-box; width: 100px; height: 50px; padding: 10px; border: 5px solid; background: red"></div>
		<div style="width: 100px; height: 50px; padding: 10px; border: 5px solid; background: blue"></div>
		<span style="box-sizing: border-box; display: inline-block; width: 60px; padding: 0 10px; background: green">a</span>
		<div style="float: left; box-sizing: border-box; width: 60px; padding: 5px; background: yellow">b</div>
		<div style="display: flex"><div style="box-sizing: border-box; width: 80px; padding: 10px; background: gray">c</div></div>
	</body>`, 400)
	defer dom.destroy(doc)
	defer destroy(l)

	if len(l.boxes) != 5 do return
	widths: [5]f32
	for box, i in l.boxes {
		widths[i] = box.width
	}
	testing.expect_value(t, l.boxes[0].height, 50)
	testing.expect_value(t, l.boxes[1].height, 80) // content-box: 50 + 2 x 15
	testing.expect_value(t, widths, [5]f32{100, 130, 60, 60, 80})
}

@(test)
test_min_width :: proc(t: ^testing.T) {
	// min-width wins over width and max-width, and widens shrink-to-fit boxes
	doc, l := build_html(t, `<body style="margin: 0">
		<div style="width: 50px; max-width: 40px; min-width: 80px; background: red">a</div>
		<span style="display: inline-block; min-width: 100px; background: blue">b</span>
	</body>`, 400)
	defer dom.destroy(doc)
	defer destroy(l)

	if len(l.boxes) != 2 do return
	testing.expect_value(t, l.boxes[0].width, 80)
	testing.expect_value(t, l.boxes[1].width, 100)
}

@(test)
test_calc_lengths :: proc(t: ^testing.T) {
	doc, l := build_html(t, `<body style="margin: 0">
		<div style="width: calc(50% - 2em); margin-left: calc(25% + 10px); height: calc(1em + 4px); background: red"></div>
		<div style="width: calc(100% - 40px); padding: 0 calc(10px - 1em); height: calc(100% - 10px); background: blue">a</div>
		<div style="display: flex"><div style="flex-basis: calc(30% + 30px); background: green">b</div></div>
	</body>`, 400)
	defer dom.destroy(doc)
	defer destroy(l)

	if len(l.boxes) != 3 do return
	red := l.boxes[0]
	testing.expect_value(t, red.width, 168) // 200 - 32
	testing.expect_value(t, red.x, 110)
	testing.expect_value(t, red.height, 20)
	blue := l.boxes[1]
	testing.expect_value(t, blue.width, 360) // negative padding counts as 0
	testing.expect_value(t, blue.height, 20) // % in calc(): auto, like a percentage height
	testing.expect_value(t, l.boxes[2].width, 150)
}

@(test)
test_percentages_in_own_context :: proc(t: ^testing.T) {
	// percentages of floats, inline blocks and absolute elements refer to the
	// containing block, not to the box they are laid out in
	doc, l := build_html(t, `<body style="margin: 0">
		<div style="float: left; width: 50%; padding-left: 10%; background: red">a</div>
		<div style="clear: both"><span style="display: inline-block; box-sizing: border-box; width: calc(50% - 6px); padding: 0 5%; background: blue">b</span></div>
		<div style="position: relative; height: 40px"><div style="position: absolute; width: 25%; margin-left: 10%; background: green">c</div></div>
	</body>`, 400)
	defer dom.destroy(doc)
	defer destroy(l)

	if len(l.boxes) != 3 do return
	testing.expect_value(t, l.boxes[0].width, 240) // 200 + 40 padding
	testing.expect_value(t, l.runs[0].x, 40)
	testing.expect_value(t, l.boxes[1].width, 194)
	testing.expect_value(t, l.runs[1].x, 20)
	testing.expect_value(t, l.boxes[2].width, 100)
	testing.expect_value(t, l.boxes[2].x, 40)
}
