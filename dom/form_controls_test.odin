package dom

import "core:strings"
import "core:testing"

@(test)
test_form_controls :: proc(t: ^testing.T) {
	doc, err := parse(`<body style="font-size: 20px; color: red">
		<input value="hello"><input placeholder="Search"><input><input type="password" value="abc">
		<input type="hidden" value="x"><input type="submit"><input type="checkbox" checked>
		<select><option>One</option><option selected>Two</option><optgroup><option label="Three">3</option></optgroup></select>
		<textarea rows="3" cols="10">text</textarea><button>Go</button><input hidden>
	</body>`)
	if e, ok := err.?; ok {
		testing.fail_now(t, e.message)
	}
	defer destroy(doc)

	body := find_element(doc.root, "body")
	inputs := make([dynamic]^Node, context.temp_allocator)
	for child in body.children {
		if child.kind == .Element {
			append(&inputs, child)
		}
	}
	value, placeholder, empty, password, hidden, submit, checkbox := inputs[0], inputs[1], inputs[2], inputs[3], inputs[4], inputs[5], inputs[6]
	select, textarea, button, hidden_attr := inputs[7], inputs[8], inputs[9], inputs[10]

	// controls have their own font and look, not the page's
	testing.expect_value(t, value.style.font_size, CONTROL_FONT_SIZE)
	testing.expect_value(t, value.style.color, Color{0, 0, 0, 255})
	testing.expect_value(t, value.style.display, Display.Inline_Block)
	testing.expect_value(t, value.style.width, em(20 * 0.54 + 1.5)) // size 20
	testing.expect_value(t, button.style.background, BUTTON_FACE)
	testing.expect_value(t, hidden.style.display, Display.None)
	testing.expect_value(t, hidden_attr.style.display, Display.None) // the hidden attribute still wins

	// what they show, as generated children
	testing.expect_value(t, generated_texts(value), "hello")
	testing.expect_value(t, generated_texts(placeholder), "Search")
	testing.expect_value(t, placeholder.children[0].style.color, PLACEHOLDER_COLOR)
	testing.expect_value(t, generated_texts(empty), " ")
	testing.expect_value(t, generated_texts(password), "•••")
	testing.expect_value(t, generated_texts(submit), "Submit Query")
	testing.expect_value(t, generated_texts(checkbox), "✓")
	testing.expect_value(t, checkbox.style.background, CHECKED_COLOR)

	// select: the selected option, the others as invisible sizers, the arrow
	testing.expect_value(t, generated_texts(select), "Two|One|Two|Three|⌄")
	for child in select.children {
		if !child.generated {
			testing.expect_value(t, child.style.display, Display.None) // options and optgroups
		}
	}

	testing.expect_value(t, textarea.style.font_family, Font_Family.Mono)
	testing.expect_value(t, textarea.style.width, em(10 * 0.6 + 0.75))
	testing.expect(t, !textarea.children[0].generated, "the text of a textarea is its own")
}

// The texts of the generated nodes in a control, joined with "|".
@(private = "file")
generated_texts :: proc(node: ^Node) -> string {
	texts := make([dynamic]string, context.temp_allocator)
	collect :: proc(node: ^Node, texts: ^[dynamic]string) {
		for child in node.children {
			if !child.generated {
				continue
			}
			if child.kind == .Text {
				append(texts, child.text)
			}
			collect(child, texts)
		}
	}
	collect(node, &texts)
	return strings.join(texts[:], "|", context.temp_allocator)
}

@(test)
test_styled_controls :: proc(t: ^testing.T) {
	// CSS wins over the UA look; "background: none" removes the grey
	doc, err := parse(`<style>
		.flat { background: none; border: 0 }
		.blue { background: #00f url(x.png) no-repeat; font-size: 20px }
	</style><button class="flat">a</button><button class="blue">b</button>`)
	if e, ok := err.?; ok {
		testing.fail_now(t, e.message)
	}
	defer destroy(doc)

	body := find_element(doc.root, "body")
	flat, blue := body.children[0], body.children[1]
	testing.expect_value(t, flat.style.background, Color{})
	testing.expect_value(t, flat.style.border[.Top].style, Border_Style.None)
	testing.expect_value(t, blue.style.background, Color{0, 0, 255, 255})
	testing.expect_value(t, blue.style.font_size, 20)
}
