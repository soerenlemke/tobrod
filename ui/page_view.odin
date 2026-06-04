package ui

import sdl "vendor:sdl3"

PageView :: struct {
	rect:     sdl.FRect,
	bg_color: sdl.Color,
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
	// TODO: how do we render the wep page here?
}

page_view_handle_resize :: proc(pv: ^PageView, window_width, window_height: i32) {
	pv.rect.w = f32(window_width)
	pv.rect.h = f32(window_height) - ADDRESS_BAR_HEIGHT
}
