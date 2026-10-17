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
	return doc, build(doc, width, fake_measure)
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
	l := build(doc, 800, fake_measure)
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
