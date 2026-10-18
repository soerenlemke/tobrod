package dom

import "core:testing"

@(test)
test_element_report :: proc(t: ^testing.T) {
	report := css_report_init()
	defer css_report_destroy(&report)
	doc, err := parse(`<html><body bgcolor="#eee">
		<form><input name="q"><input type="hidden" name="t"><input type="range"><button>Go</button></form>
		<p>Some <em>italic</em> and <code>code</code>, x<sup>2</sup>.</p>
		<img src="logo.svg?v=2" width="20" height="20"><img src="photo.webp"><img src="a.png">
		<details><summary>More</summary>hidden</details><details open>shown</details>
		<noscript>Please enable JavaScript</noscript>
		<table cellpadding="4"><tr><td bgcolor="red" align="right" width="50%" background="x.png">a</td></tr></table>
		<hr noshade><dialog>hidden</dialog>
		<my-widget></my-widget><svg width="10"><rect width="5" height="5"></rect></svg><svg><g><use href="#a"></use></g></svg>
		<div style="display: none"><select><option>a</option></select><td bgcolor="red"></td></div>
	</body></html>`, report = &report)
	if e, ok := err.?; ok {
		testing.fail_now(t, e.message)
	}
	defer destroy(doc)

	testing.expect_value(t, report.elements["input: range"], 1) // the other inputs are drawn
	testing.expect(t, !("button" in report.elements), "buttons are drawn")
	testing.expect(t, !("em" in report.elements), "italic is drawn")
	testing.expect(t, !("img: SVG" in report.elements), "SVG images are drawn")
	testing.expect_value(t, report.elements["img: WebP"], 1)
	testing.expect_value(t, report.elements["dialog"], 1) // not open
	testing.expect_value(t, report.elements["noscript"], 1)
	testing.expect_value(t, report.elements["custom elements"], 1)
	testing.expect(t, !("select" in report.elements), "inside display: none")
	testing.expect(t, !("img" in report.elements), "PNG is supported")

	testing.expect_value(t, report.attributes["td[background]"], 1)
	testing.expect_value(t, report.attributes["hr[noshade]"], 1)
	for supported in ([]string{"body[bgcolor]", "td[bgcolor]", "td[align]", "td[width]", "table[cellpadding]"}) {
		testing.expectf(t, !(supported in report.attributes), "%s is read (html_hints.odin)", supported)
	}
	testing.expect(t, !("img[width]" in report.attributes), "image sizes are read")
	testing.expect(t, !("input[name]" in report.attributes), "not presentational")
	// inline SVG is drawn; only the parts our renderer can't draw count
	testing.expect(t, !("svg" in report.elements), "inline SVG is drawn")
	testing.expect_value(t, report.elements["svg: use"], 1)
	testing.expect(t, !("rect[width]" in report.attributes), "parts of an SVG")

	testing.expect_value(t, element_gap_reason("svg: use"), "SVG with <use>, the reused part is missing")
}
