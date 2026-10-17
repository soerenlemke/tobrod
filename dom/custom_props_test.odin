package dom

import "core:testing"

@(test)
test_substitute_vars :: proc(t: ^testing.T) {
	props := make(Custom_Props, allocator = context.temp_allocator)
	props["--color"] = "#202122"
	props["--space"] = "8px"
	props["--both"] = "var(--space) var(--space)"
	props["--a"] = "var(--b)"
	props["--b"] = "var(--a)"

	cases := []struct {
		value, result: string,
		ok:            bool,
	} {
		{"var(--color)", "#202122", true},
		{"VAR(--color)", "#202122", true},
		{"var(--space) 0", "8px 0", true},
		{"var(--both)", "8px 8px", true},                 // nested
		{"var(--missing, red)", "red", true},             // fallback
		{"var(--missing, var(--color))", "#202122", true},
		{"rgb(var(--missing, 1, 2, 3))", "rgb(1, 2, 3)", true}, // the fallback keeps its commas
		{"var(--missing)", "", false},                    // no fallback: invalid
		{"var(--a)", "", false},                          // cycle
		{"calc(var(--space) * 2)", "calc(8px * 2)", true},
	}
	for c in cases {
		result, ok := substitute_vars(c.value, &props)
		testing.expectf(t, ok == c.ok && (!ok || result == c.result), "%q: got %q %v", c.value, result, ok)
	}
}

@(test)
test_css_variables_in_parse :: proc(t: ^testing.T) {
	doc, err := parse(`<html><head><style>
		:root { --text: #202122; --gap: 12px; --accent: var(--text) }
		p { color: red; color: var(--text) }
		.note { --text: #36c; margin: var(--gap) 0 }
		.important { color: green !important }
		.fallback { color: var(--nope, rgb(1, 2, 3)) }
		.broken { color: blue; color: var(--nope) }
		.nested { color: var(--accent) }
	</style></head><body>
		<p>plain</p>
		<p class="note">note <span>inner</span></p>
		<p class="important">important</p>
		<p class="fallback">fallback</p>
		<p class="broken">broken</p>
		<p class="nested">nested</p>
		<div style="--text: #ff0000"><p>inline var</p></div>
	</body></html>`)
	if e, ok := err.?; ok {
		testing.fail_now(t, e.message)
	}
	defer destroy(doc)

	ps := make([dynamic]^Node, context.temp_allocator)
	collect :: proc(node: ^Node, out: ^[dynamic]^Node) {
		for child in node.children {
			if child.kind == .Element && child.tag == "p" {
				append(out, child)
			}
			collect(child, out)
		}
	}
	collect(doc.root, &ps)
	testing.expect_value(t, len(ps), 7)
	if len(ps) != 7 do return

	text := Color{0x20, 0x21, 0x22, 255}
	testing.expect_value(t, ps[0].style.color, text)                          // var wins over the plain value before it
	testing.expect_value(t, ps[1].style.color, Color{0x33, 0x66, 0xcc, 255})  // --text overridden on .note
	testing.expect_value(t, ps[1].style.margin[.Top], px(12))                 // var in a shorthand
	testing.expect_value(t, ps[1].children[1].style.color, Color{0x33, 0x66, 0xcc, 255}) // inherited
	testing.expect_value(t, ps[2].style.color, Color{0, 128, 0, 255})         // !important beats the var
	testing.expect_value(t, ps[3].style.color, Color{1, 2, 3, 255})           // fallback
	testing.expect_value(t, ps[4].style.color, Color{0, 0, 0, 255})           // invalid var wins, becomes unset: inherited, not blue
	testing.expect_value(t, ps[5].style.color, text)                          // custom property referring to another
	testing.expect_value(t, ps[6].style.color, Color{255, 0, 0, 255})         // custom property from style=""
}

@(test)
test_values_lexbor_cannot_parse :: proc(t: ^testing.T) {
	// lexbor stores `clear: both` as an unknown value; we parse the raw text.
	// An invalid raw value must not wipe out a valid earlier one.
	doc, err := parse(`<html><head><style>
		h2 { clear: both }
		p { color: red; color: notacolor }
	</style></head><body><h2>h</h2><p>p</p></body></html>`)
	if e, ok := err.?; ok {
		testing.fail_now(t, e.message)
	}
	defer destroy(doc)
	testing.expect_value(t, find_element(doc.root, "h2").style.clear, Clear.Both)
	testing.expect_value(t, find_element(doc.root, "p").style.color, Color{255, 0, 0, 255})
}
