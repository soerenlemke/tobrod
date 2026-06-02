package ui

import "core:strings"
import sdl "vendor:sdl3"

Ui_AddressBar :: struct {
	rect:         sdl.FRect, // for position and size
	text:         strings.Builder, // input text
	focused:      bool,
	bg_color:     sdl.Color,
	border_color: sdl.Color,
}

ui_address_bar_init :: proc(window_width: i32) -> Ui_AddressBar {
	bar := Ui_AddressBar {
		rect = sdl.FRect{x = 0, y = 0, w = f32(window_width), h = 36},
		focused = false,
		bg_color = sdl.Color{240, 240, 240, 255},
		border_color = sdl.Color{180, 180, 180, 255},
	}
	strings.builder_init(&bar.text)

	return bar
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

	// render text
	if len(bar.text.buf) > 0 {
		text_c := strings.to_cstring(&bar.text)
		texture := ui_fonts_render_text_to_texture(ui.renderer, text_c, {30, 30, 30, 255})

		if texture != nil {
			defer sdl.DestroyTexture(texture)

			text_width, text_height: f32
			sdl.GetTextureSize(texture, &text_width, &text_height)

			dst := sdl.FRect {
				x = input_rect.x + 6,
				y = input_rect.y + (input_rect.h - text_height) / 2,
				w = text_width,
				h = text_height,
			}
			sdl.RenderTexture(ui.renderer, texture, nil, &dst)
		}
	}
}

ui_address_bar_handle_event :: proc(ui: ^Ui_Window, bar: ^Ui_AddressBar, event: ^sdl.Event) {
	#partial switch event.type {
	case .MOUSE_BUTTON_DOWN:
		mx := f32(event.button.x)
		my := f32(event.button.y)

		bar.focused =
			mx >= bar.rect.x &&
			mx <= bar.rect.x + bar.rect.w &&
			my >= bar.rect.y &&
			my <= bar.rect.y + bar.rect.h

		// TODO: should we handle the return values of these?
		if bar.focused {
			_ = sdl.StartTextInput(ui.window)
		} else {
			_ = sdl.StopTextInput(ui.window)
		}

	case .TEXT_INPUT:
		if bar.focused {
			strings.write_string(&bar.text, string(event.text.text))
		}

	case .KEY_DOWN:
		if bar.focused {
			switch event.key.key {
			case sdl.K_BACKSPACE:
				s := strings.to_string(bar.text)
				if len(s) > 0 {
					strings.builder_reset(&bar.text)
					strings.write_string(&bar.text, s[:len(s) - 1])
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
