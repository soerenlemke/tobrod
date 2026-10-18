package dom

import "core:testing"

@(test)
test_logical_mapping :: proc(t: ^testing.T) {
	cases := []struct {
		property: string,
		physical: [2]string,
		split:    bool,
	} {
		{"margin-inline-start", {0 = "margin-left"}, false},
		{"padding-block-end", {0 = "padding-bottom"}, false},
		{"margin-block", {"margin-top", "margin-bottom"}, true},
		{"padding-inline", {"padding-left", "padding-right"}, true},
		{"border-inline-start", {0 = "border-left"}, false},
		{"border-block-end-color", {0 = "border-bottom-color"}, false},
		{"border-inline-width", {"border-left-width", "border-right-width"}, true},
		{"border-block", {"border-top", "border-bottom"}, false}, // "1px solid" for both
		{"inset-inline-end", {0 = "right"}, false},
		{"inset-block", {"top", "bottom"}, true},
		{"max-inline-size", {0 = "max-width"}, false},
		{"border-end-start-radius", {0 = "border-bottom-left-radius"}, false},
	}
	for c in cases {
		m, ok := logical_mapping(c.property)
		testing.expectf(t, ok && m.physical == c.physical && m.split == c.split, "%s: %v %v", c.property, m, ok)
	}
	for p in LOGICAL_PROPERTIES {
		_, ok := logical_mapping(p)
		testing.expectf(t, ok, "%s has a mapping", p)
	}
}

@(test)
test_logical_properties :: proc(t: ^testing.T) {
	doc, err := parse(`<style>
		.a { margin: 0; margin-inline-start: 2em; padding-block: 1px 3px; inline-size: 50% }
		.b { border-block-end: 2px solid red; inset-inline: 4px }
		.c .d { margin-left: 7px }
		.d { margin-inline-start: 9px; padding-inline: 5px }
	</style><div class="a"></div><div class="b"></div><div class="c"><div class="d"></div></div>`)
	if e, ok := err.?; ok {
		testing.fail_now(t, e.message)
	}
	defer destroy(doc)

	body := find_element(doc.root, "body")
	a, b := body.children[0], body.children[1]
	d := body.children[2].children[0]

	// after the physical margin: the logical one wins
	testing.expect_value(t, a.style.margin[.Left], em(2))
	testing.expect_value(t, a.style.margin[.Right], px(0))
	testing.expect_value(t, a.style.padding[.Top], px(1))
	testing.expect_value(t, a.style.padding[.Bottom], px(3))
	testing.expect_value(t, a.style.width, Length{unit = .Percent, value = 50})

	testing.expect_value(t, b.style.border[.Bottom].width, px(2))
	testing.expect_value(t, b.style.border[.Bottom].style, Border_Style.Solid)
	testing.expect_value(t, b.style.border[.Top].style, Border_Style.None)
	testing.expect_value(t, b.style.offset[.Left], px(4))
	testing.expect_value(t, b.style.offset[.Right], px(4))

	// a more specific physical declaration wins over the logical one
	testing.expect_value(t, d.style.margin[.Left], px(7))
	testing.expect_value(t, d.style.padding[.Left], px(5))
}
