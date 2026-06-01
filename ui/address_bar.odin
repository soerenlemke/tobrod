package ui

import sdl "vendor:sdl3"

// TODO: real text rendering with SDL3_ttf?
// should we write our own bindings for SDL_ttf.h?

Ui_AddressBar :: struct {
	rect:         sdl.FRect, // for position and size
	text:         [dynamic]u8, // input text
	focused:      bool,
	bg_color:     sdl.Color,
	border_color: sdl.Color,
}

ui_address_bar_init :: proc(window_width: i32) -> Ui_AddressBar {
	return Ui_AddressBar {
		rect = sdl.FRect{x = 0, y = 0, w = f32(window_width), h = 36},
		text = make([dynamic]u8),
		focused = false,
		bg_color = sdl.Color{240, 240, 240, 255},
		border_color = sdl.Color{180, 180, 180, 255},
	}
}

ui_address_bar_render :: proc(ui: ^Ui_Window, bar: ^Ui_AddressBar) {
	// background
	sdl.SetRenderDrawColor(
		ui.renderer,
		bar.bg_color.r,
		bar.bg_color.g,
		bar.bg_color.b,
		bar.bg_color.a,
	)
	sdl.RenderFillRect(ui.renderer, &bar.rect)

	// border bottom
	sdl.SetRenderDrawColor(
		ui.renderer,
		bar.bg_color.r,
		bar.bg_color.g,
		bar.bg_color.b,
		bar.bg_color.a,
	)
	bottom_line := sdl.FRect{0, bar.rect.h - 1, bar.rect.w, 1}
	sdl.RenderFillRect(ui.renderer, &bottom_line)

	// input field
	input_rect := sdl.FRect {
		x = 80, // space for icons/buttons on the left
		y = 6,
		w = bar.rect.w - 160, // space for reload etc. on the right
		h = 24,
	}
	sdl.SetRenderDrawColor(ui.renderer, 255, 255, 255, 255)
	sdl.RenderFillRect(ui.renderer, &input_rect)

	// focus border
	if bar.focused {
		sdl.SetRenderDrawColor(ui.renderer, 66, 133, 244, 255)
	} else {
		sdl.SetRenderDrawColor(ui.renderer, 200, 200, 200, 255)
	}
	sdl.RenderRect(ui.renderer, &input_rect)
}

ui_address_bar_handle_event :: proc(bar: ^Ui_AddressBar, event: ^sdl.Event) {
	#partial switch event.type {
	case .MOUSE_BUTTON_DOWN:
		mx := f32(event.button.x)
		my := f32(event.button.y)

		bar.focused =
			mx >= bar.rect.x &&
			mx <= bar.rect.x + bar.rect.w &&
			my >= bar.rect.y &&
			my <= bar.rect.y + bar.rect.h

		// TODO: should we handle the return values this?
		if bar.focused {
			_ = sdl.StartTextInput(nil)
		} else {
			_ = sdl.StopTextInput(nil)
		}

	case .TEXT_INPUT:
		if bar.focused {
			text := string(event.text.text)
			for ch in text {
				if ch == 0 do break
				append(&bar.text, u8(ch))
			}
		}

	case .KEY_DOWN:
		if bar.focused {
			switch event.key.key {
			case sdl.K_BACKSPACE:
				if len(bar.text) > 0 {
					pop(&bar.text)
				}
			case sdl.K_RETURN:
				// TODO: callback/event navigate to url
				_ = sdl.StopTextInput(nil)
				bar.focused = false
			case sdl.K_ESCAPE:
				_ = sdl.StopTextInput(nil)
				bar.focused = false
			}

		}
	}
}
