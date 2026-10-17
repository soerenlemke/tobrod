package dom

import "core:testing"

@(test)
test_media_query_matches :: proc(t: ^testing.T) {
	desktop := Media_Env{1200, 800}
	cases := []struct {
		query: string,
		match: bool,
	} {
		{"", true},
		{"screen", true},
		{"all", true},
		{"print", false},
		{"print, screen", true},
		{"not print", true},
		{"only screen", true},
		{"screen and (min-width: 1120px)", true},
		{"screen and (min-width: 1680px)", false},
		{"screen and (max-width: calc(1120px - 1px))", false},
		{"all and (max-width:calc(640px - 1px))", false},
		{"(min-width: 40em)", true}, // 640px
		{"screen and (prefers-color-scheme: dark)", false},
		{"(prefers-color-scheme: light)", true},
		{"(width >= 640px)", true},
		{"(width < 1120px)", false},
		{"(orientation: landscape)", true},
		{"(min-resolution: 2dppx)", false}, // unknown -> no match
		{"SCREEN AND (MIN-WIDTH: 1px)", true},
	}
	for c in cases {
		testing.expectf(t, media_query_list_matches(c.query, desktop) == c.match, "%q: expected %v", c.query, c.match)
	}
}

@(test)
test_apply_media_queries :: proc(t: ^testing.T) {
	env := Media_Env{1200, 800}
	css := `a{color:red}
@media screen{b{color:blue}@media (max-width:600px){c{color:green}}}
/* @media in a comment { stays */
@media print{d{x:"}"}}
e{content:"@media"}`

	out := apply_media_queries(css, env)
	defer delete(out)
	expected := `a{color:red}
b{color:blue}

/* @media in a comment { stays */

e{content:"@media"}`
	testing.expect_value(t, out, expected)

	// for <style> elements: only what was inside matching @media blocks
	only := apply_media_queries(css, env, only_media = true)
	defer delete(only)
	testing.expect_value(t, only, "b{color:blue}\n")
}

@(test)
test_media_in_parse :: proc(t: ^testing.T) {
	html := `<html><head><style>
		p { color: red }
		@media (min-width: 800px) { p { color: blue } }
		@media print { div { display: none } }
	</style><link rel="stylesheet" href="a.css"></head><body><p>x</p><div>y</div><span>z</span></body></html>`

	load := proc(ctx: rawptr, href: string) -> (css: string, ok: bool) {
		return "@media screen and (max-width: 600px) { span { display: none } }", true
	}

	// wide: the min-width rule matches, the max-width rule doesn't
	doc, err := parse(html, {load = load}, Media_Env{1000, 700})
	if e, ok := err.?; ok {
		testing.fail_now(t, e.message)
	}
	testing.expect_value(t, find_element(doc.root, "p").style.color, Color{0, 0, 255, 255})
	testing.expect_value(t, find_element(doc.root, "div").style.display, Display.Block) // print ignored
	testing.expect_value(t, find_element(doc.root, "span").style.display, Display.Inline)
	destroy(doc)

	// narrow: the other way round
	doc, err = parse(html, {load = load}, Media_Env{500, 700})
	if e, ok := err.?; ok {
		testing.fail_now(t, e.message)
	}
	defer destroy(doc)
	testing.expect_value(t, find_element(doc.root, "p").style.color, Color{255, 0, 0, 255})
	testing.expect_value(t, find_element(doc.root, "span").style.display, Display.None)
}
