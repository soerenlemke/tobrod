package dom

import "core:testing"

@(test)
test_html_hints :: proc(t: ^testing.T) {
	doc, err := parse(`<html><body bgcolor="ff6600" text="#333">
		<center>centered</center>
		<table width="85%" cellpadding="4" cellspacing="0" border="2" align="center">
			<tr valign="top"><td bgcolor="#f6f6ef" align="right" width="18">a</td><th>b</th></tr>
		</table>
		<table><tr><td>c</td></tr></table>
		<p align="center">p</p>
		<font color="red" size="+2">big</font>
		<style>.x { text-align: left }</style>
		<div align="right" class="x">css wins</div>
		x<sup>2</sup> H<sub>2</sub>O
	</body></html>`)
	if e, ok := err.?; ok {
		testing.fail_now(t, e.message)
	}
	defer destroy(doc)

	body := find_element(doc.root, "body")
	testing.expect_value(t, body.style.background, Color{0xff, 0x66, 0x00, 255}) // no #
	testing.expect_value(t, body.style.color, Color{0x33, 0x33, 0x33, 255})

	center := find_element(doc.root, "center")
	testing.expect_value(t, center.style.display, Display.Block)
	testing.expect_value(t, center.style.text_align, Text_Align.Legacy_Center)

	table := find_element(doc.root, "table")
	testing.expect_value(t, table.style.width, Length{unit = .Percent, value = 85})
	testing.expect_value(t, table.style.border_spacing, 0)
	testing.expect_value(t, table.style.border[.Left].width, px(2))
	testing.expect_value(t, table.style.margin[.Left].unit, Length_Unit.Auto)
	testing.expect_value(t, table.style.text_align, Text_Align.Left) // <center> stops at tables

	td := find_element(doc.root, "td")
	testing.expect_value(t, td.style.background, Color{0xf6, 0xf6, 0xef, 255})
	testing.expect_value(t, td.style.text_align, Text_Align.Right)
	testing.expect_value(t, td.style.width, px(18))
	testing.expect_value(t, td.style.padding[.Top], px(4))
	testing.expect_value(t, td.style.border[.Top].width, px(1)) // cells of a table with border
	testing.expect_value(t, td.style.vertical_align, Vertical_Align.Top) // from the tr

	th := find_element(doc.root, "th")
	testing.expect_value(t, th.style.vertical_align, Vertical_Align.Top)

	tds: [dynamic]^Node
	defer delete(tds)
	collect_tag(doc.root, "td", &tds)
	plain_td := tds[1] // in the table without attributes
	testing.expect_value(t, plain_td.style.vertical_align, Vertical_Align.Middle)
	testing.expect_value(t, plain_td.style.border[.Top].style, Border_Style.None)
	testing.expect_value(t, plain_td.style.padding[.Top], px(1))

	testing.expect_value(t, find_element(doc.root, "p").style.text_align, Text_Align.Legacy_Center)
	font := find_element(doc.root, "font")
	testing.expect_value(t, font.style.color, Color{255, 0, 0, 255})
	testing.expect_value(t, font.style.font_size, 24)
	testing.expect_value(t, find_element(doc.root, "div").style.text_align, Text_Align.Left)

	sup := find_element(doc.root, "sup")
	testing.expect_value(t, sup.style.vertical_align, Vertical_Align.Super)
	testing.expect(t, sup.style.font_size < 16, "sup is smaller")
	testing.expect_value(t, find_element(doc.root, "sub").style.vertical_align, Vertical_Align.Sub)
}

@(test)
test_details :: proc(t: ^testing.T) {
	doc, err := parse(`<details><summary>One</summary><p>hidden</p>text<summary>second</summary></details>
		<details open><summary>Two</summary><p>shown</p></details>`)
	if e, ok := err.?; ok {
		testing.fail_now(t, e.message)
	}
	defer destroy(doc)

	body := find_element(doc.root, "body")
	closed, open := body.children[0], body.children[2]
	testing.expect_value(t, closed.tag, "details")
	testing.expect_value(t, open.tag, "details")

	summary := closed.children[0]
	testing.expect_value(t, summary.style.display, Display.List_Item)
	testing.expect_value(t, summary.style.list_style, List_Style.Disclosure_Closed)
	testing.expect(t, summary.style.list_inside, "the triangle is inside")
	testing.expect(t, !hidden_by_details(summary), "the summary is shown")
	testing.expect_value(t, closed.children[1].style.display, Display.None)
	testing.expect(t, hidden_by_details(closed.children[2]), "text in a closed details")
	testing.expect_value(t, closed.children[3].style.display, Display.None) // only the first summary

	testing.expect_value(t, open.children[0].style.list_style, List_Style.Disclosure_Open)
	testing.expect_value(t, open.children[1].style.display, Display.Block)
}

@(private = "file")
collect_tag :: proc(node: ^Node, tag: string, result: ^[dynamic]^Node) {
	if node.kind == .Element && node.tag == tag {
		append(result, node)
	}
	for child in node.children {
		collect_tag(child, tag, result)
	}
}
