package dom

import "core:testing"

@(test)
test_grid_style :: proc(t: ^testing.T) {
	// Wikipedia's header and MDN-like templates: shorthand, minmax, repeat,
	// line names, areas; item placement by name, lines and span
	doc, err := parse(`<style>
		.g { display: grid; grid-template: auto / 15.5rem minmax(0,1fr); grid-template-areas: 'headerStart headerEnd'; gap: 4px 8px }
		.h { display: inline-grid; grid-template-columns: [full-start] repeat(2, 100px) [x] repeat(auto-fill, minmax(50px, 1fr)) }
		.a { grid-area: headerEnd } .b { grid-column: 1 / -1; grid-row: span 2 } .c { grid-area: 2 / 1 / 4 / 3 }
		</style><div class="g"><p class="a"></p><p class="b"></p><p class="c"></p></div><span class="h"></span>`)
	if e, ok := err.?; ok {
		testing.fail_now(t, e.message)
	}
	defer destroy(doc)

	g := find_element(doc.root, "div").style
	testing.expect_value(t, g.display, Display.Grid)
	testing.expect_value(t, len(g.grid.columns), 2)
	if len(g.grid.columns) == 2 {
		testing.expect_value(t, g.grid.columns[0].min.length, px(15.5 * 16))
		testing.expect_value(t, g.grid.columns[1].min.length, px(0))
		testing.expect_value(t, g.grid.columns[1].max, Track_Size{kind = .Fr, fr = 1})
	}
	testing.expect_value(t, len(g.grid.areas), 2)
	if len(g.grid.areas) == 2 {
		testing.expect_value(t, g.grid.areas[1], Grid_Area{"headerend", 1, 2, 2, 3})
	}
	testing.expect_value(t, g.flex.row_gap, px(4))
	testing.expect_value(t, g.flex.column_gap, px(8))

	h := find_element(doc.root, "span").style
	testing.expect_value(t, h.display, Display.Inline_Grid)
	testing.expect_value(t, len(h.grid.columns), 2)
	testing.expect_value(t, h.grid.auto_repeat.at, 2)
	testing.expect_value(t, len(h.grid.auto_repeat.tracks), 1)

	items := find_element(doc.root, "div").children
	if len(items) < 3 {
		testing.fail_now(t, "three items")
	}
	a, b, c := items[0].style.grid, items[1].style.grid, items[2].style.grid
	testing.expect_value(t, a.column.start.name, "headerend")
	testing.expect_value(t, a.row.end.name, "headerend")
	testing.expect_value(t, b.column, Grid_Placement{{kind = .Line, value = 1}, {kind = .Line, value = -1}})
	testing.expect_value(t, b.row.start, Grid_Line{kind = .Span, value = 2})
	testing.expect_value(t, c.row, Grid_Placement{{kind = .Line, value = 2}, {kind = .Line, value = 4}})
	testing.expect_value(t, c.column, Grid_Placement{{kind = .Line, value = 1}, {kind = .Line, value = 3}})
	testing.expect_value(t, items[0].style.display, Display.Block)
}
