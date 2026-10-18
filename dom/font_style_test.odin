package dom

import "core:testing"

@(test)
test_parse_font_family :: proc(t: ^testing.T) {
	cases := []struct {
		value:  string,
		family: Font_Family,
		ok:     bool,
	} {
		{"monospace", .Mono, true},
		{`"SFMono-Regular", Consolas, "Liberation Mono", Menlo, monospace`, .Mono, true},
		{"'Courier New', Courier", .Mono, true},
		{`-apple-system, BlinkMacSystemFont, "Segoe UI", Consolas`, .Sans, true}, // the first one we know wins
		{`"Inter", sans-serif`, .Sans, true},
		{"Georgia, serif", .Sans, true}, // no serif font: sans
		{`"Some Web Font"`, .Sans, false}, // nothing we know: keep the inherited one
	}
	for c in cases {
		family, ok := parse_font_family(c.value)
		testing.expectf(t, family == c.family && ok == c.ok, "%s: %v %v", c.value, family, ok)
	}
}

@(test)
test_font_styles :: proc(t: ^testing.T) {
	doc, err := parse(`<html><head><style>
		.mono { font-family: Menlo, monospace }
		.short { font: italic bold 20px/30px "Fira Code", monospace }
		.reset { font: 12px Arial, sans-serif }
		.upright { font-style: normal }
	</style></head><body>
		<p><code>code</code> <em>em <span class="upright">upright</span></em> <cite>cite</cite></p>
		<pre>pre <code>nested</code></pre>
		<div class="mono">mono <i>italic</i></div>
		<div class="short">short</div>
		<b><em><span class="reset">reset</span></em></b>
	</body></html>`)
	if e, ok := err.?; ok {
		testing.fail_now(t, e.message)
	}
	defer destroy(doc)

	code := find_element(doc.root, "code")
	testing.expect_value(t, code.style.font_family, Font_Family.Mono)
	testing.expect_value(t, code.style.font_size, 13) // 16 x 13/16, like browsers

	em := find_element(doc.root, "em")
	testing.expect(t, em.style.font_italic, "em is italic")
	testing.expect(t, !find_class(doc.root, "upright").style.font_italic, "font-style: normal")
	testing.expect(t, find_element(doc.root, "cite").style.font_italic, "cite is italic")

	pre := find_element(doc.root, "pre")
	testing.expect_value(t, pre.style.font_size, 13)
	nested := pre.children[1]
	testing.expect_value(t, nested.style.font_size, 13) // not made smaller twice

	mono := find_class(doc.root, "mono")
	testing.expect_value(t, mono.style.font_family, Font_Family.Mono)
	testing.expect_value(t, mono.style.font_size, 16) // only the UA makes monospace smaller
	testing.expect_value(t, mono.children[1].style.font_family, Font_Family.Mono) // inherited

	short := find_class(doc.root, "short")
	testing.expect(t, short.style.font_italic, "italic from the shorthand")
	testing.expect_value(t, short.style.font_weight, 700)
	testing.expect_value(t, short.style.font_size, 20)
	testing.expect_value(t, short.style.font_family, Font_Family.Mono)
	testing.expect_value(t, line_height_px(short.style), 30)

	// the shorthand resets what it doesn't name
	reset := find_class(doc.root, "reset")
	testing.expect(t, !reset.style.font_italic, "font resets the style")
	testing.expect_value(t, reset.style.font_weight, 400)
	testing.expect_value(t, reset.style.font_size, 12)
}

@(private = "file")
find_class :: proc(node: ^Node, class: string) -> ^Node {
	if value, ok := attribute(node, "class"); ok && value == class {
		return node
	}
	for child in node.children {
		if found := find_class(child, class); found != nil {
			return found
		}
	}
	return nil
}
