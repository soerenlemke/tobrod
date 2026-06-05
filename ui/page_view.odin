package ui

import "core:strings"
import sdl "vendor:sdl3"

PageView :: struct {
	rect:     sdl.FRect,
	bg_color: sdl.Color,
	content:  string,
}

PageViewRenderer :: struct {
	// TODO
}

page_view_init :: proc(window_width, window_height: i32) -> PageView {
	return PageView {
		rect = sdl.FRect {
			x = 0,
			y = f32(ADDRESS_BAR_HEIGHT),
			w = f32(window_width),
			h = f32(window_height) - f32(ADDRESS_BAR_HEIGHT),
		},
		bg_color = sdl.Color{255, 255, 255, 255},
	}
}

page_view_render :: proc(ui: ^MainWindow, pv: ^PageView) {
	sdl.SetRenderDrawColor(ui.renderer, pv.bg_color.r, pv.bg_color.g, pv.bg_color.b, pv.bg_color.a)
	sdl.RenderFillRect(ui.renderer, &pv.rect)

	if len(pv.content) > 0 {
		text_c := strings.clone_to_cstring(pv.content)
		defer delete(text_c)
		texture := fonts_render_text_to_texture(ui.renderer, text_c, {30, 30, 30, 255})

		if texture != nil {
			defer sdl.DestroyTexture(texture)

			text_width, text_height: f32
			sdl.GetTextureSize(texture, &text_width, &text_height)
			dst := sdl.FRect {
				x = pv.rect.x,
				y = pv.rect.y,
				w = text_width,
				h = text_height,
			}
			sdl.RenderTexture(ui.renderer, texture, nil, &dst)
		}
	}
}

page_view_handle_resize :: proc(pv: ^PageView, window_width, window_height: i32) {
	pv.rect.w = f32(window_width)
	pv.rect.h = f32(window_height) - ADDRESS_BAR_HEIGHT
}
