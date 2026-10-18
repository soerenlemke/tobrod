package layout

import "core:strings"
import "core:testing"
import "../dom"

// The texts of the runs in paint order, layer by layer: "flow|a b|c".
@(private = "file")
paint_order :: proc(l: ^Layout) -> string {
	b := strings.builder_make(context.temp_allocator)
	for layer, i in l.layers {
		if i > 0 {
			strings.write_string(&b, "|")
		}
		for run, j in l.runs[layer.runs[0]:layer.runs[1]] {
			if j > 0 {
				strings.write_string(&b, " ")
			}
			strings.write_string(&b, run.text)
		}
	}
	return strings.to_string(b)
}

@(private = "file")
layout_html :: proc(t: ^testing.T, html: string) -> (doc: ^dom.Document, l: ^Layout) {
	err: Maybe(dom.Parse_Error)
	doc, err = dom.parse(html)
	if e, ok := err.?; ok {
		testing.fail_now(t, e.message)
	}
	measure :: proc(text: string, font_size: f32, font: Font) -> f32 {
		return f32(len(text)) * font_size * 0.5
	}
	return doc, build(doc, {400, 600}, measure)
}

@(test)
test_z_index_order :: proc(t: ^testing.T) {
	cases := []struct {
		html, want: string,
	} {
		// positioned elements over the flow, in document order
		{`<div style="position: relative">a</div><p>flow</p><div style="position: absolute">b</div>`, "flow|a|b"},
		// z-index sorts them; negative ones go below the flow
		{`<div style="position: relative; z-index: 2">a</div><div style="position: relative; z-index: 1">b</div><div style="position: relative; z-index: -1">c</div><p>flow</p>`, "c|flow|b|a"},
		// the same z-index: document order; auto counts like 0
		{`<div style="position: relative; z-index: 1">a</div><div style="position: relative">b</div><div style="position: relative; z-index: 0">c</div><div style="position: relative; z-index: 1">d</div>`, "|b|c|a|d"},
		// a z-index is a stacking context: what is inside stays in its layer
		{`<div style="position: relative; z-index: 1">a<div style="position: relative; z-index: 9">b</div></div><div style="position: relative; z-index: 2">c</div>`, "|a b|c"},
		// z-index: auto isn't: an inner element with a z-index gets its own layer
		{`<div style="position: relative">a<div style="position: relative; z-index: 9">b</div></div><div style="position: relative; z-index: 2">c</div>`, "|a|c|b"},
	}
	for c in cases {
		doc, l := layout_html(t, c.html)
		testing.expectf(t, paint_order(l) == c.want, "%s:\n%s", c.html, paint_order(l))
		destroy(l)
		dom.destroy(doc)
	}
}
