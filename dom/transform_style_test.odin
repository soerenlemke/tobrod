package dom

import "core:math"
import "core:testing"

@(test)
test_transform_style :: proc(t: ^testing.T) {
	cases := []struct {
		value: string,
		count: int,
		ok:    bool,
	} {
		{"translate(-50%, -50%)", 1, true},
		{"translateY(calc(-1 * 4px)) scaleY(0.5)", 2, true},
		{"rotate(90deg) translateZ(0)", 1, true}, // translateZ has no 2D effect
		{"rotate(.25turn)", 1, true},
		{"matrix(1, 0, 0, 1, 10, 20)", 1, true},
		{"wobble(3)", 0, false},
		{"rotate(45)", 0, false}, // an angle needs a unit
	}
	for c in cases {
		tr, ok := parse_transform_list(c.value)
		testing.expectf(t, ok == c.ok && tr.count == c.count, "%s: %v %d", c.value, ok, tr.count)
	}
	r, _ := parse_transform_list("rotate(.25turn)")
	testing.expect(t, abs(r.list[0].a[0] - math.PI / 2) < 1e-5, "a quarter turn")
	s, _ := parse_transform_list("translate(-50%, -50%)")
	testing.expect_value(t, s.list[0].x, Length{unit = .Percent, value = -50})

	doc, err := parse(`<div style="transform-origin: left top; transform: scale(2)"></div>`)
	if e, failed := err.?; failed {
		testing.fail_now(t, e.message)
	}
	defer destroy(doc)
	div := find_element(doc.root, "div").style.transform
	testing.expect_value(t, div.count, 1)
	testing.expect_value(t, div.origin, Maybe([2]Length)([2]Length{{unit = .Percent}, {unit = .Percent}}))
}
