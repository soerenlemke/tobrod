package dom

import "core:strings"
import "core:testing"

@(test)
test_parse_color :: proc(t: ^testing.T) {
	current := Color{1, 2, 3, 255}
	cases := []struct {
		value: string,
		color: Color,
		ok:    bool,
	} {
		{"red", {255, 0, 0, 255}, true},
		{"#f00", {255, 0, 0, 255}, true},
		{"#ff000080", {255, 0, 0, 128}, true},
		{"#12345", {}, false},
		{"rgb(255, 0, 0)", {255, 0, 0, 255}, true},
		{"rgba(255, 0, 0, 0.5)", {255, 0, 0, 128}, true},
		{"rgb(255 0 0 / 50%)", {255, 0, 0, 128}, true},
		{"rgb(100%, 0%, 0%)", {255, 0, 0, 255}, true},
		{"currentcolor", current, true},
		{"transparent", {0, 0, 0, 0}, true},
		{"hsl(0, 100%, 50%)", {}, false},
	}
	for c in cases {
		color, ok := parse_color(c.value, current)
		testing.expectf(t, ok == c.ok && (!ok || color == c.color), "%q: got %v %v", c.value, color, ok)
	}
}

@(test)
test_parse_font_size :: proc(t: ^testing.T) {
	parent := f32(20)
	cases := []struct {
		value: string,
		px:    f32,
		ok:    bool,
	} {
		{"12px", 12, true},
		{"1.5em", 30, true},
		{"2rem", 32, true},
		{"50%", 10, true},
		{"12pt", 16, true},
		{"medium", 16, true},
		{"larger", 24, true},
		{"0", 0, true},
		{"12", 0, false},
		{"12vw", 0, false},
	}
	for c in cases {
		px, ok := parse_font_size(c.value, parent)
		testing.expectf(t, ok == c.ok && (!ok || abs(px - c.px) < 0.01), "%q: got %v %v", c.value, px, ok)
	}
}

@(test)
test_parse_font_weight :: proc(t: ^testing.T) {
	cases := []struct {
		value:  string,
		parent: int,
		weight: int,
		ok:     bool,
	} {
		{"normal", 700, 400, true},
		{"bold", 400, 700, true},
		{"600", 400, 600, true},
		{"bolder", 400, 700, true},
		{"bolder", 700, 900, true},
		{"lighter", 700, 400, true},
		{"1001", 400, 0, false},
	}
	for c in cases {
		weight, ok := parse_font_weight(c.value, c.parent)
		testing.expectf(t, ok == c.ok && (!ok || weight == c.weight), "%q (parent %v): got %v %v", c.value, c.parent, weight, ok)
	}
}

@(test)
test_computed_styles :: proc(t: ^testing.T) {
	doc, err := parse(`<html><head><style>
		body { color: #333; font-size: 20px }
		.note { font-size: 0.5em; color: inherit }
		.red { color: red }
		h1 { font-weight: normal }
	</style></head><body>
		<p>plain <span>span</span></p>
		<p class="red">red <b>bold</b> <a href="/">link</a></p>
		<p class="note">note</p>
		<h1>h1</h1><h2>h2</h2>
	</body></html>`)
	if e, ok := err.?; ok {
		testing.fail_now(t, e.message)
	}
	defer destroy(doc)

	body := find_element(doc.root, "body")
	ps := children_with_tag(body, "p")
	defer delete(ps)
	testing.expect_value(t, len(ps), 3)

	grey := Color{0x33, 0x33, 0x33, 255}

	// inherited from body
	span := find_element(ps[0], "span")
	testing.expect_value(t, span.style.color, grey)
	testing.expect_value(t, span.style.font_size, 20)
	testing.expect_value(t, span.style.font_weight, 400)

	// author color is inherited by <b>; <a> keeps its own default link color
	b := find_element(ps[1], "b")
	testing.expect_value(t, b.style.color, Color{255, 0, 0, 255})
	testing.expect_value(t, b.style.font_weight, 700)
	a := find_element(ps[1], "a")
	testing.expect_value(t, a.style.color, LINK_COLOR)

	// em is relative to the parent's font size
	testing.expect_value(t, ps[2].style.font_size, 10)
	testing.expect_value(t, ps[2].style.color, grey)

	// tag defaults: h1 is 2em, but author CSS overrides its weight; h2 keeps bold
	h1 := find_element(body, "h1")
	testing.expect_value(t, h1.style.font_size, 40)
	testing.expect_value(t, h1.style.font_weight, 400)
	h2 := find_element(body, "h2")
	testing.expect_value(t, h2.style.font_size, 30)
	testing.expect_value(t, h2.style.font_weight, 700)
}

// Depth-first search for the first element with the tag (shared by the tests
// of this package).
@(private)
find_element :: proc(node: ^Node, tag: string) -> ^Node {
	for child in node.children {
		if child.kind == .Element && child.tag == tag {
			return child
		}
		if found := find_element(child, tag); found != nil {
			return found
		}
	}
	return nil
}

@(private = "file")
children_with_tag :: proc(node: ^Node, tag: string) -> [dynamic]^Node {
	result: [dynamic]^Node
	for child in node.children {
		if child.kind == .Element && child.tag == tag {
			append(&result, child)
		}
	}
	return result
}

@(test)
test_box_shorthands :: proc(t: ^testing.T) {
	e, ok := parse_edges("1em 2px 3% auto", true)
	testing.expect(t, ok, "expected 4 values to parse")
	testing.expect_value(t, e[.Top], em(1))
	testing.expect_value(t, e[.Right], px(2))
	testing.expect_value(t, e[.Bottom], Length{.Percent, 3})
	testing.expect_value(t, e[.Left], AUTO)

	e, ok = parse_edges("0 auto", true)
	testing.expect(t, ok && e[.Top] == px(0) && e[.Right] == AUTO && e[.Bottom] == px(0) && e[.Left] == AUTO, "two values: vertical horizontal")

	_, ok = parse_edges("auto", false)
	testing.expect(t, !ok, "padding has no auto")
	_, ok = parse_edges("1px 2px 3px 4px 5px", true)
	testing.expect(t, !ok, "at most four values")

	color, color_ok := background_color_of("#222 url(x.png) no-repeat", {})
	testing.expect(t, color_ok && color == Color{0x22, 0x22, 0x22, 255}, "color from background shorthand")
	color, color_ok = background_color_of("url(a b.png) rgb(1, 2, 3)", {})
	testing.expect(t, color_ok && color == Color{1, 2, 3, 255}, "spaces inside parentheses don't split")
	color, color_ok = parse_color("light-dark(#eee, #222)", {})
	testing.expect(t, color_ok && color == Color{0xee, 0xee, 0xee, 255}, "light-dark takes the light color")
}

@(test)
test_box_styles_from_css :: proc(t: ^testing.T) {
	doc, err := parse(`<html><head><style>
		div { margin: 0 auto; max-width: 20em; padding: 4px 8px; background: #abc }
		div { margin-top: 10px }
	</style></head><body><div>x</div><ul></ul></body></html>`)
	if e, ok := err.?; ok {
		testing.fail_now(t, e.message)
	}
	defer destroy(doc)

	body := find_element(doc.root, "body")
	testing.expect_value(t, body.style.margin[.Left], px(8)) // UA default

	div := find_element(doc.root, "div")
	// the longhand margin-top wins over the shorthand
	testing.expect_value(t, div.style.margin, edges(px(10), AUTO, px(0), AUTO))
	testing.expect_value(t, div.style.padding, edges(px(4), px(8), px(4), px(8)))
	testing.expect_value(t, div.style.max_width, em(20))
	testing.expect_value(t, div.style.width, AUTO)
	testing.expect_value(t, div.style.background, Color{0xaa, 0xbb, 0xcc, 255})

	ul := find_element(doc.root, "ul")
	testing.expect_value(t, ul.style.padding[.Left], px(40))
}

@(test)
test_border_parsing :: proc(t: ^testing.T) {
	red := Color{255, 0, 0, 255}
	b, ok := parse_border("1px solid red", {})
	testing.expect(t, ok && b.width == px(1) && b.style == .Solid && b.color == red, "width style color")
	b, ok = parse_border("red dashed thick", {})
	testing.expect(t, ok && b.width == px(5) && b.style == .Solid && b.color == red, "any order, dashed drawn solid")
	b, ok = parse_border("solid", {})
	testing.expect(t, ok && b.width == px(3) && b.color == nil, "missing parts get initial values")
	b, ok = parse_border("1px solid rgb(1, 2, 3)", {})
	testing.expect(t, ok && b.color == Color{1, 2, 3, 255}, "spaces inside rgb() don't split")
	_, ok = parse_border("1px solid red blue", {})
	testing.expect(t, !ok, "at most three parts")
	_, ok = parse_border_width("10%")
	testing.expect(t, !ok, "no percentages for border widths")
}

@(test)
test_borders_and_align_from_css :: proc(t: ^testing.T) {
	doc, err := parse(`<html><head><style>
		body { text-align: center }
		div { border: 2px solid blue; border-left: none; border-bottom-color: red }
		p { text-align: right }
	</style></head><body><div><p>x</p><span>y</span></div><hr></body></html>`)
	if e, ok := err.?; ok {
		testing.fail_now(t, e.message)
	}
	defer destroy(doc)

	div := find_element(doc.root, "div")
	testing.expect_value(t, div.style.text_align, Text_Align.Center) // inherited from body
	testing.expect_value(t, div.style.border[.Top].width, px(2))
	testing.expect_value(t, div.style.border[.Left].style, Border_Style.None)
	testing.expect_value(t, div.style.border[.Bottom].color.?, Color{255, 0, 0, 255})
	testing.expect_value(t, div.style.border[.Right].color.?, Color{0, 0, 255, 255})

	p := find_element(doc.root, "p")
	testing.expect_value(t, p.style.text_align, Text_Align.Right)

	hr := find_element(doc.root, "hr")
	testing.expect_value(t, hr.style.border[.Top].style, Border_Style.Solid) // UA default
}

@(test)
test_viewport_units :: proc(t: ^testing.T) {
	length, ok := parse_length("25vh", false)
	testing.expect(t, ok, "vh parses")
	testing.expect_value(t, resolve_length(length, 16, 0, {1000, 600}), 150)
	length, _ = parse_length("10vw", false)
	testing.expect_value(t, resolve_length(length, 16, 0, {1000, 600}), 100)
}

@(test)
test_external_stylesheets :: proc(t: ^testing.T) {
	html := `<html><head>
		<link rel="stylesheet" href="a.css">
		<link rel="stylesheet" href="print.css" media="print">
		<link rel="alternate stylesheet" href="alt.css">
		<link rel="icon" href="x.ico">
		<link rel="stylesheet" href="missing.css">
		<style>p { font-weight: bold }</style>
	</head><body><p>x</p><div>y</div></body></html>`

	Fake :: struct {
		requested: [dynamic]string,
	}
	fake: Fake
	defer {
		for href in fake.requested {
			delete(href)
		}
		delete(fake.requested)
	}

	load := proc(ctx: rawptr, href: string) -> (css: string, ok: bool) {
		fake := cast(^Fake)ctx
		// href points into lexbor's memory, which is gone after parse: keep a copy
		append(&fake.requested, strings.clone(href))
		switch href {
		case "a.css":
			return "p { color: red } div { display: none }", true
		case "print.css", "alt.css":
			return "p { color: blue }", true
		}
		return "", false // missing.css
	}

	doc, err := parse(html, {load = load, ctx = &fake})
	if e, ok := err.?; ok {
		testing.fail_now(t, e.message)
	}
	defer destroy(doc)

	// only real, non-print stylesheets are requested, in document order
	testing.expect_value(t, len(fake.requested), 2)
	if len(fake.requested) == 2 {
		testing.expect_value(t, fake.requested[0], "a.css")
		testing.expect_value(t, fake.requested[1], "missing.css")
	}

	p := find_element(doc.root, "p")
	testing.expect_value(t, p.style.color, Color{255, 0, 0, 255})  // from a.css
	testing.expect_value(t, p.style.font_weight, 700)               // <style> still works
	div := find_element(doc.root, "div")
	testing.expect_value(t, div.style.display, Display.None)
}

@(test)
test_position_visibility_list_style :: proc(t: ^testing.T) {
	doc, err := parse(`<html><head><style>
		.menu { visibility: hidden; list-style: none }
		.menu .shown { visibility: visible }
		.popup { position: absolute }
		ol.square { list-style-type: square }
	</style></head><body>
		<ul class="menu"><li>a</li><li class="shown">b</li></ul>
		<div class="popup">p</div>
		<ol><li>1</li></ol>
		<ol class="square"><li>x</li></ol>
	</body></html>`)
	if e, ok := err.?; ok {
		testing.fail_now(t, e.message)
	}
	defer destroy(doc)

	menu := find_element(doc.root, "ul")
	testing.expect_value(t, menu.style.visibility, Visibility.Hidden)
	testing.expect_value(t, menu.children[0].style.visibility, Visibility.Hidden) // inherited
	testing.expect_value(t, menu.children[0].style.list_style, List_Style.None)   // inherited
	testing.expect_value(t, menu.children[1].style.visibility, Visibility.Visible)

	testing.expect_value(t, find_element(doc.root, "div").style.position, Position.Absolute)

	ol := find_element(doc.root, "ol")
	testing.expect_value(t, ol.children[0].style.list_style, List_Style.Decimal) // UA default for ol
	ok_square := false
	for child in find_element(doc.root, "body").children {
		if child.kind == .Element && child.tag == "ol" && len(child.attributes) > 0 {
			ok_square = child.children[0].style.list_style == .Square
		}
	}
	testing.expect(t, ok_square, "list-style-type: square inherited by the li")
}

@(test)
test_flex_properties :: proc(t: ^testing.T) {
	doc, err := parse(`<html><head><style>
		.box { display: flex; flex-flow: column wrap; justify-content: space-between; align-items: center; gap: 4px 8px }
		.a { flex: 1 }
		.b { flex: 2 0 100px; align-self: flex-end }
		.c { flex: none }
	</style></head><body><div class="box"><span class="a">a</span><div class="b">b</div><div class="c" style="float: left">c</div></div></body></html>`)
	if e, ok := err.?; ok {
		testing.fail_now(t, e.message)
	}
	defer destroy(doc)

	box := find_element(doc.root, "div")
	f := box.style.flex
	testing.expect_value(t, box.style.display, Display.Flex)
	testing.expect_value(t, f.direction, Flex_Direction.Column)
	testing.expect(t, f.wrap, "flex-flow: wrap")
	testing.expect_value(t, f.justify, Justify.Space_Between)
	testing.expect_value(t, f.align_items, Align.Center)
	testing.expect_value(t, f.row_gap, px(4))
	testing.expect_value(t, f.column_gap, px(8))

	items := make([dynamic]^Node, context.temp_allocator)
	for child in box.children {
		if child.kind == .Element {
			append(&items, child)
		}
	}
	a, b, c := items[0], items[1], items[2]
	testing.expect_value(t, a.style.display, Display.Block) // blockified
	testing.expect(t, a.style.flex.grow == 1 && a.style.flex.shrink == 1 && a.style.flex.basis == px(0), "flex: 1")
	testing.expect(t, b.style.flex.grow == 2 && b.style.flex.shrink == 0 && b.style.flex.basis == px(100), "flex: 2 0 100px")
	testing.expect_value(t, b.style.flex.align_self, Align_Self.End)
	testing.expect(t, c.style.flex.grow == 0 && c.style.flex.shrink == 0, "flex: none")
	testing.expect_value(t, c.style.float, Float.None) // floats don't apply to flex items
}
