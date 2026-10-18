package dom

import "core:testing"

@(test)
test_element_report :: proc(t: ^testing.T) {
	report := css_report_init()
	defer css_report_destroy(&report)
	doc, err := parse(`<html><body bgcolor="#eee">
		<form><input name="q"><input type="hidden" name="t"><button>Go</button></form>
		<p>Some <em>italic</em> and <code>code</code>, x<sup>2</sup>.</p>
		<img src="logo.svg?v=2" width="20" height="20"><img src="photo.webp"><img src="a.png">
		<details><summary>More</summary>hidden</details><details open>shown</details>
		<noscript>Please enable JavaScript</noscript>
		<table cellpadding="4"><tr><td bgcolor="red" align="right" width="50%">a</td></tr></table>
		<my-widget></my-widget><svg width="10"><rect width="5" height="5"></rect></svg>
		<div style="display: none"><select><option>a</option></select><td bgcolor="red"></td></div>
	</body></html>`, report = &report)
	if e, ok := err.?; ok {
		testing.fail_now(t, e.message)
	}
	defer destroy(doc)

	testing.expect_value(t, report.elements["input"], 1) // not the hidden one
	testing.expect_value(t, report.elements["button"], 1)
	testing.expect_value(t, report.elements["em"], 1)
	testing.expect_value(t, report.elements["code"], 1)
	testing.expect_value(t, report.elements["sup"], 1)
	testing.expect_value(t, report.elements["img: SVG"], 1)
	testing.expect_value(t, report.elements["img: WebP"], 1)
	testing.expect_value(t, report.elements["details"], 1) // not the open one
	testing.expect_value(t, report.elements["noscript"], 1)
	testing.expect_value(t, report.elements["custom elements"], 1)
	testing.expect(t, !("select" in report.elements), "inside display: none")
	testing.expect(t, !("img" in report.elements), "PNG is supported")

	testing.expect_value(t, report.attributes["body[bgcolor]"], 1)
	testing.expect_value(t, report.attributes["td[bgcolor]"], 1) // the hidden one doesn't count
	testing.expect_value(t, report.attributes["td[align]"], 1)
	testing.expect_value(t, report.attributes["td[width]"], 1)
	testing.expect_value(t, report.attributes["table[cellpadding]"], 1)
	testing.expect(t, !("img[width]" in report.attributes), "image sizes are read")
	testing.expect(t, !("input[name]" in report.attributes), "not presentational")
	testing.expect_value(t, report.elements["svg"], 1)
	testing.expect(t, !("rect[width]" in report.attributes), "parts of an SVG")

	testing.expect_value(t, element_gap_reason("select"), "form control, all options as text")
}
