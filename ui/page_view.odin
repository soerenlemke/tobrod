package ui

import "core:strings"
import rl "vendor:raylib"

PageView :: struct {
	rect:           rl.Rectangle,
	bg_color:       rl.Color,
	content:        string,
	scroll_y:       f32,
	content_height: f32,
}

page_view_init :: proc(window_width, window_height: i32) -> PageView {
	return PageView {
		rect = rl.Rectangle {
			x = 0,
			y = f32(ADDRESS_BAR_HEIGHT),
			width = f32(window_width),
			height = f32(window_height) - f32(ADDRESS_BAR_HEIGHT),
		},
		bg_color = rl.Color{255, 255, 255, 255},
	}
}

page_view_render :: proc(pv: ^PageView) {
	rl.BeginScissorMode(i32(pv.rect.x), i32(pv.rect.y), i32(pv.rect.width), i32(pv.rect.height))
	defer rl.EndScissorMode()

	rl.DrawRectangleRec(pv.rect, pv.bg_color)

	if len(pv.content) > 0 {
		text_c := strings.clone_to_cstring(pv.content)
		defer delete(text_c)

		font_size: f32 = 16
		size := rl.MeasureTextEx(font, text_c, font_size, 0)
		pv.content_height = size.y

		pos := rl.Vector2{pv.rect.x, pv.rect.y - pv.scroll_y}
		rl.DrawTextEx(font, text_c, pos, font_size, 0, rl.Color{30, 30, 30, 255})
	}
}

page_view_handle_resize :: proc(pv: ^PageView, window_width, window_height: i32) {
	pv.rect.width = f32(window_width)
	pv.rect.height = f32(window_height) - ADDRESS_BAR_HEIGHT
}

page_view_handle_scroll :: proc(pv: ^PageView, wheel_y: f32, content_height: f32) {
	pv.scroll_y -= wheel_y * PAGE_VIEW_SCROLL_SPEED
	pv.scroll_y = max(pv.scroll_y, 0)

	// limit scrolling when content is smaller than view
	max_scroll := max(content_height - pv.rect.height, 0)
	pv.scroll_y = min(pv.scroll_y, max_scroll)
}
