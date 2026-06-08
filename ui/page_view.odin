package ui

import sdl "vendor:sdl3"

PageView :: struct {
	rect:     sdl.FRect,
	bg_color: sdl.Color,
	content:  string,
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
	sdl.SetRenderDrawColor(
		ui.renderer.sdl_renderer,
		pv.bg_color.r,
		pv.bg_color.g,
		pv.bg_color.b,
		pv.bg_color.a,
	)
	sdl.RenderFillRect(ui.renderer.sdl_renderer, &pv.rect)

	if len(pv.content) > 0 {
		texture := renderer_get_text_texture(
			&ui.renderer,
			pv.content,
			{30, 30, 30, 255},
			pv.rect.w,
		)

		if texture != nil {
			text_width, text_height: f32
			sdl.GetTextureSize(texture, &text_width, &text_height)
			dst := sdl.FRect {
				x = pv.rect.x,
				y = pv.rect.y,
				w = text_width,
				h = text_height,
			}
			sdl.RenderTexture(ui.renderer.sdl_renderer, texture, nil, &dst)
		}
	}
}

page_view_handle_resize :: proc(pv: ^PageView, r: ^Renderer, window_width, window_height: i32) {
	pv.rect.w = f32(window_width)
	pv.rect.h = f32(window_height) - ADDRESS_BAR_HEIGHT

	renderer_invalidate_text_cache(r, pv.content) // needed for getting a new texture that fits the new window size
}
