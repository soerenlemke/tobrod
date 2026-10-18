package dom

import "core:testing"

@(test)
test_parse_calc :: proc(t: ^testing.T) {
	viewport := [2]f32{1000, 600}
	// resolved with font size 10 and a containing block 200px wide
	cases := []struct {
		value: string,
		px:    f32,
		ok:    bool,
	} {
		{"calc(1120px - 1px)", 1119, true},
		{"calc(100% - 2em)", 180, true},
		{"calc(50% + 10px)", 110, true},
		{"calc(2 * 1rem)", 32, true},
		{"calc(1em * 3)", 30, true},
		{"calc(100% / 4)", 50, true},
		{"calc(10vw - 1em)", 90, true},
		{"calc((100% - 20px) / 2)", 90, true},
		{"calc(100% - calc(2 * 10px))", 180, true},
		{"calc( 1px + 2px )", 3, true},
		{"calc(1px + 2px - 3px)", 0, true},
		{"calc(-1em + 5px)", -5, true},
		{"calc(1px\t+\n2px)", 3, true},
		{"calc(100%-2em)", 0, false}, // + and - need spaces
		{"calc(100% -2em)", 0, false},
		{"calc(1px * 2px)", 0, false}, // an area, not a length
		{"calc(1px / 0)", 0, false},
		{"calc(2 / 1px)", 0, false},
		{"calc(1 + 2px)", 0, false},
		{"calc(3)", 0, false}, // a number, not a length
		{"calc(1px + 2px", 0, false},
		{"calc(1px) 2px", 0, false},
		{"calc(min(1px, 2px))", 0, false},
		{"calc(1ch)", 0, false},
	}
	for c in cases {
		length, ok := parse_calc(c.value)
		testing.expectf(t, ok == c.ok, "%q: ok = %v", c.value, ok)
		if ok && c.ok {
			testing.expectf(t, resolve_length(length, 10, 200, viewport) == c.px, "%q: %v", c.value, resolve_length(length, 10, 200, viewport))
		}
	}
}

@(test)
test_calc_single_unit :: proc(t: ^testing.T) {
	// a result in one unit is a normal length, only mixed units need .Calc
	length, _ := parse_calc("calc(1120px - 1px)")
	testing.expect_value(t, length, px(1119))
	length, _ = parse_calc("calc(50% * 2)")
	testing.expect_value(t, length, Length{unit = .Percent, value = 100})
	length, _ = parse_calc("calc(100% - 2em)")
	testing.expect_value(t, length.unit, Length_Unit.Calc)
	testing.expect(t, has_percent(length), "100% - 2em depends on the containing block")
	testing.expect(t, !is_zero(length), "a calc() is not 0")
}

@(test)
test_calc_in_style :: proc(t: ^testing.T) {
	doc, err := parse(`<div style="margin: 0 calc(10% + 4px); width: calc(100% - 2em); padding-left: calc(1em / 2)">a</div>`)
	if e, ok := err.?; ok {
		testing.fail_now(t, e.message)
	}
	defer destroy(doc)

	div := find_element(doc.root, "div")
	testing.expect_value(t, resolve_length(div.style.margin[.Left], 16, 200, {}), 24)
	testing.expect_value(t, resolve_length(div.style.margin[.Top], 16, 200, {}), 0)
	testing.expect_value(t, resolve_length(div.style.width, 16, 200, {}), 168)
	testing.expect_value(t, div.style.padding[.Left], em(0.5))
}
