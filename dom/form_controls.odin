package dom

import "core:mem"
import "core:strconv"
import "core:strings"

// Form controls (<input>, <button>, <select>, <textarea>), drawn the way
// Firefox draws them, but only to look at: nothing can be typed or clicked
// yet. Two parts:
//
// 1. Their user agent style (form_control_style): a 13.33px font that is not
//    inherited, grey borders with slightly rounded corners, a light grey
//    background for buttons, and sizes from attributes (size, rows, cols).
//    Measured on Firefox's screenshots of testdata/forms.html.
// 2. What they show: an <input> has no children, its value or placeholder is
//    drawn by the browser; a <select> shows its selected option and an arrow.
//    Browsers build a hidden "shadow" tree for that. We add generated child
//    nodes (Node.generated) after parsing (add_form_content); for anyone
//    walking the DOM they are not part of the page.

CONTROL_FONT_SIZE :: f32(13.333) // Firefox's -moz-field font
CONTROL_BORDER :: Color{129, 127, 132, 255}
BUTTON_FACE :: Color{233, 233, 237, 255}
PLACEHOLDER_COLOR :: Color{117, 117, 117, 255}
DISABLED_COLOR :: Color{109, 109, 109, 255}
CHECKED_COLOR :: Color{0, 96, 223, 255}

// The type of an <input>, lowercase; unknown types are text fields.
input_type :: proc(node: ^Node) -> string {
	type, _ := attribute(node, "type")
	type = strings.to_lower(strings.trim_space(type), context.temp_allocator)
	switch type {
	case "hidden", "checkbox", "radio", "submit", "reset", "button", "image", "file", "password":
		return type
	}
	return "text"
}

// The UA style of form controls and their parts, after default_style (and
// before the CSS).
@(private)
form_control_style :: proc(node: ^Node, style: ^Style) {
	switch node.tag {
	case "option", "optgroup":
		if node.parent != nil && (node.parent.tag == "select" || node.parent.tag == "optgroup") {
			style.display = .None // the select shows its selected option itself
		}
	case "fieldset":
		style.margin = edges(px(0), px(2), px(0), px(2))
		style.padding = edges(em(0.35), em(0.75), em(0.625), em(0.75))
		set_border(style, 2, Color{192, 192, 192, 255})
	case "legend":
		// browsers put it into the top border of the fieldset; we put it on top
		style.display = .Block
		style.padding = edges(px(0), px(2), px(0), px(2))
	case "button":
		control_look(node, style)
		button_look(style)
	case "select":
		control_look(node, style)
		button_look(style)
		style.text_align = .Left
		style.padding[.Right] = px(22) // room for the arrow
		style.position = .Relative // the arrow is placed at its right edge
	case "textarea":
		control_look(node, style)
		style.font_family = .Mono
		cols := attribute_int(node, "cols", 20)
		rows := attribute_int(node, "rows", 2)
		// a monospace character is 0.6em wide; padding and border are inside
		style.width = em(f32(cols) * 0.6 + 0.75)
		style.height = px(f32(rows) * NORMAL_LINE_HEIGHT * CONTROL_FONT_SIZE + 6)
		style.overflow = {.Hidden, .Hidden}
	case "input":
		control_look(node, style)
		switch input_type(node) {
		case "hidden":
			style.display = .None
		case "submit", "reset", "button", "image":
			button_look(style)
		case "file":
			// a button and a text next to it (add_form_content)
			style.border = INITIAL_BORDERS
			style.background = {}
			style.padding = {}
		case "checkbox", "radio":
			check_look(node, style)
		case:
			// text fields: as wide as size characters (in Firefox about
			// 0.54em each, plus padding and border)
			size := attribute_int(node, "size", 20)
			style.width = em(f32(size) * 0.54 + 1.5)
		}
	}
}

// What all controls share: their own font (not the page's), a grey border
// with slightly rounded corners, a white background.
@(private)
control_look :: proc(node: ^Node, style: ^Style) {
	style.font_size = CONTROL_FONT_SIZE
	style.font_weight = 400
	style.font_italic = false
	style.font_family = .Sans
	style.line_height = {}
	style.color = {0, 0, 0, 255}
	if _, disabled := attribute(node, "disabled"); disabled {
		style.color = DISABLED_COLOR
	}
	style.text_align = .Left
	if style.display != .None { // the hidden attribute
		style.display = .Inline_Block
	}
	style.border_box = true
	set_border(style, 1, CONTROL_BORDER)
	set_radius(style, px(4))
	style.background = {255, 255, 255, 255}
	style.padding = edges(px(2), px(3), px(2), px(3))
}

@(private)
button_look :: proc(style: ^Style) {
	style.background = BUTTON_FACE
	style.padding = edges(px(2), px(6), px(2), px(6))
	style.text_align = .Center
}

// A 14px box (a circle for radios); checked: a blue box (with a white check
// mark, added by add_form_content) or a blue ring around a white dot.
@(private)
check_look :: proc(node: ^Node, style: ^Style) {
	radio := input_type(node) == "radio"
	style.padding = {}
	style.width, style.height = px(14), px(14)
	style.margin = edges(px(3), px(3), px(3), px(4))
	set_radius(style, Length{unit = .Percent, value = 50} if radio else px(2))
	style.font_size = 11
	style.text_align = .Center
	style.line_height = {.Px, 12}
	// with overflow, an inline block sits on its bottom edge, not on the
	// baseline of its text: checked (with a check mark) and unchecked boxes
	// line up
	style.overflow = {.Hidden, .Hidden}
	if _, checked := attribute(node, "checked"); checked {
		if radio {
			set_border(style, 4, CHECKED_COLOR)
		} else {
			set_border(style, 1, CHECKED_COLOR)
			style.background = CHECKED_COLOR
		}
	}
}

@(private)
set_border :: proc(style: ^Style, width: f32, color: Color) {
	for edge in Edge {
		style.border[edge] = {px(width), .Solid, color}
	}
}

@(private)
set_radius :: proc(style: ^Style, radius: Length) {
	for corner in Corner {
		style.border_radius[corner] = radius
	}
}

@(private)
attribute_int :: proc(node: ^Node, name: string, default: int) -> int {
	value, ok := attribute(node, name)
	if !ok {
		return default
	}
	n, valid := strconv.parse_int(strings.trim_space(value))
	return n if valid && n > 0 else default
}

// Adds what a control shows as generated children; called once the
// element and its children are copied (the options of a select).
@(private)
add_form_content :: proc(node: ^Node, allocator: mem.Allocator) {
	switch node.tag {
	case "input":
		add_input_content(node, allocator)
	case "select":
		add_select_content(node, allocator)
	}
}

@(private)
add_input_content :: proc(node: ^Node, allocator: mem.Allocator) {
	value, has_value := attribute(node, "value")
	switch input_type(node) {
	case "hidden", "image", "radio":
	case "checkbox":
		if _, checked := attribute(node, "checked"); checked {
			mark := generated_element(node, "span", allocator)
			mark.style.color = {255, 255, 255, 255}
			generated_text(mark, "✓", allocator)
		}
	case "submit":
		generated_text(node, value if has_value else "Submit Query", allocator)
	case "reset":
		generated_text(node, value if has_value else "Reset", allocator)
	case "button":
		generated_text(node, value if value != "" else " ", allocator)
	case "file":
		button := generated_element(node, "span", allocator)
		control_look(node, &button.style)
		button_look(&button.style)
		generated_text(button, "Browse…", allocator)
		generated_text(node, " No file selected.", allocator)
	case:
		text := value
		if input_type(node) == "password" {
			text = strings.repeat("•", strings.rune_count(value), context.temp_allocator)
		}
		if text != "" {
			generated_text(node, text, allocator)
		} else if placeholder, ok := attribute(node, "placeholder"); ok && placeholder != "" {
			span := generated_element(node, "span", allocator)
			span.style.color = PLACEHOLDER_COLOR
			generated_text(span, placeholder, allocator)
		} else {
			// an empty field still has a line of text: its baseline lines
			// it up with the text around it
			generated_text(node, " ", allocator)
		}
	}
}

// The selected option (or the first) and an arrow. The other options are
// there too, invisible and 0px high: they make the select as wide as its
// widest option, like in a browser.
@(private)
add_select_content :: proc(node: ^Node, allocator: mem.Allocator) {
	options := make([dynamic]^Node, context.temp_allocator)
	collect_options(node, &options)
	selected: ^Node
	for option in options {
		if _, ok := attribute(option, "selected"); ok {
			selected = option
		}
	}
	if selected == nil && len(options) > 0 {
		selected = options[0]
	}

	shown := generated_element(node, "div", allocator)
	generated_text(shown, option_label(selected) if selected != nil else " ", allocator)
	for option in options {
		sizer := generated_element(node, "div", allocator)
		sizer.style.height = px(0)
		sizer.style.overflow = {.Hidden, .Hidden}
		sizer.style.visibility = .Hidden
		generated_text(sizer, option_label(option), allocator)
	}
	arrow := generated_element(node, "span", allocator)
	arrow.style.position = .Absolute
	arrow.style.offset[.Right] = px(6)
	arrow.style.offset[.Top] = px(1)
	generated_text(arrow, "⌄", allocator)
}

@(private)
collect_options :: proc(node: ^Node, options: ^[dynamic]^Node) {
	for child in node.children {
		if child.kind != .Element || child.generated {
			continue
		}
		switch child.tag {
		case "option":
			append(options, child)
		case "optgroup":
			collect_options(child, options)
		}
	}
}

// The text of an <option>: its label attribute, or its text.
@(private)
option_label :: proc(option: ^Node) -> string {
	if label, ok := attribute(option, "label"); ok {
		return label
	}
	b := strings.builder_make(context.temp_allocator)
	for child in option.children {
		if child.kind == .Text {
			strings.write_string(&b, child.text)
		}
	}
	return strings.trim_space(strings.to_string(b))
}

// A generated element: inherits from its parent like any element.
@(private)
generated_element :: proc(parent: ^Node, tag: string, allocator: mem.Allocator) -> ^Node {
	node := new_node(.Element, parent, allocator)
	node.tag = tag
	node.generated = true
	node.style = default_style(tag, false, parent.style)
	return node
}

@(private)
generated_text :: proc(parent: ^Node, text: string, allocator: mem.Allocator) -> ^Node {
	node := new_node(.Text, parent, allocator)
	node.text = strings.clone(text, allocator)
	node.generated = true
	return node
}
