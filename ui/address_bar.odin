package ui

import "core:strings"
import rl "vendor:raylib"

AddressBar :: struct {
	rect:         rl.Rectangle,
	text:         strings.Builder,
	focused:      bool,
	bg_color:     rl.Color,
	border_color: rl.Color,
}

address_bar_init :: proc(window_width: i32) -> AddressBar {
	bar := AddressBar {
		rect = rl.Rectangle{x = 0, y = TAB_BAR_HEIGHT, width = f32(window_width), height = ADDRESS_BAR_HEIGHT},
		focused = false,
		bg_color = rl.Color{240, 240, 240, 255},
		border_color = rl.Color{180, 180, 180, 255},
	}
	strings.builder_init(&bar.text)
	return bar
}

address_bar_set_text :: proc(bar: ^AddressBar, text: string) {
	strings.builder_reset(&bar.text)
	strings.write_string(&bar.text, text)
}

address_bar_render :: proc(bar: ^AddressBar) {
	rl.DrawRectangleRec(bar.rect, bar.bg_color)

	// border bottom
	bottom_line := rl.Rectangle{0, bar.rect.y + bar.rect.height - 1, bar.rect.width, 1}
	rl.DrawRectangleRec(bottom_line, bar.border_color)

	// input field
	input_rect := address_bar_input_rect(bar)
	rl.DrawRectangleRec(input_rect, rl.WHITE)

	// focus border
	focus_color := bar.focused ? rl.Color{66, 133, 244, 255} : rl.Color{200, 200, 200, 255}
	rl.DrawRectangleLinesEx(input_rect, 1, focus_color)

	// render text
	if strings.builder_len(bar.text) > 0 {
		text_c := strings.clone_to_cstring(strings.to_string(bar.text))
		defer delete(text_c)

		font_size: f32 = 16
		size := rl.MeasureTextEx(font, text_c, font_size, 0)

		pos := rl.Vector2{input_rect.x + 6, input_rect.y + (input_rect.height - size.y) / 2}
		rl.DrawTextEx(font, text_c, pos, font_size, 0, rl.Color{30, 30, 30, 255})
	}
}

// The text field: right of the navigation buttons, up to the right edge.
address_bar_input_rect :: proc(bar: ^AddressBar) -> rl.Rectangle {
	left := NAV_BUTTONS_LEFT + NAV_BUTTONS_WIDTH + 8
	return rl.Rectangle {
		x      = left,
		y      = bar.rect.y + 6,
		width  = max(bar.rect.width - left - 8, 0),
		height = 24,
	}
}

address_bar_handle_resize :: proc(bar: ^AddressBar, window_width, window_height: i32) {
	bar.rect.width = f32(window_width)
}

address_bar_handle_input :: proc(ui: ^MainWindow, bar: ^AddressBar) {
	// only the text field takes focus, not the buttons next to it
	if rl.IsMouseButtonPressed(.LEFT) {
		bar.focused = rl.CheckCollisionPointRec(rl.GetMousePosition(), address_bar_input_rect(bar))
	}

	if !bar.focused do return

	// raylib can deliver multiple characters per frame, so use a loop instead of a single event
	for {
		key := rl.GetCharPressed()
		if key == 0 do break
		strings.write_rune(&bar.text, key)
	}

	// pop a whole rune, not a byte, so multi-byte UTF-8 chars (e.g. umlauts) stay valid
	if rl.IsKeyPressed(.BACKSPACE) && strings.builder_len(bar.text) > 0 {
		strings.pop_rune(&bar.text)
	}

	if rl.IsKeyPressed(.ENTER) {
		if ui.on_url_submit != nil {
			ui.on_url_submit(strings.to_string(bar.text), ui.on_url_submit_ctx)
		}
		bar.focused = false
	}

	if rl.IsKeyPressed(.ESCAPE) {
		bar.focused = false
	}
}
