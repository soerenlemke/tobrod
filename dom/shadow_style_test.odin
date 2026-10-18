package dom

import "core:testing"

@(test)
test_box_shadow :: proc(t: ^testing.T) {
	// two shadows (commas inside rgba() don't split), inset with a color
	// first, currentcolor, none, an invalid one keeps the old value
	cases := []struct {
		value: string,
		count: int,
		ok:    bool,
	} {
		{"0 1px 1px 0 #25292e1a, 0 3px 6px rgba(0, 0, 0, 0.2)", 2, true},
		{"#36c inset 0 0 0 1px", 1, true},
		{"4px 4px", 1, true},
		{"none", 0, true},
		{"1px", 0, false},
		{"0 0 -2px red", 0, false},
	}
	for c in cases {
		shadows, ok := parse_box_shadow(c.value, {1, 2, 3, 255})
		testing.expectf(t, ok == c.ok && shadows.count == c.count, "%s: %v %d", c.value, ok, shadows.count)
	}
	two, _ := parse_box_shadow("0 1px 1px 0 #25292e1a, 0 3px 6px rgba(0, 0, 0, 0.2)", {})
	testing.expect_value(t, two.list[1].blur, px(6))
	testing.expect_value(t, two.list[1].color, Maybe(Color)(Color{0, 0, 0, 51}))
	inset, _ := parse_box_shadow("#36c inset 0 0 0 1px", {})
	testing.expect(t, inset.list[0].inset, "inset")
	testing.expect_value(t, inset.list[0].spread, px(1))
	current, _ := parse_box_shadow("4px 4px", {})
	testing.expect_value(t, current.list[0].color, nil)
}
