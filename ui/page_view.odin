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
		lines := wrap_text(pv.content, pv.rect.width)
		pv.content_height = f32(len(lines)) * LINE_HEIGHT

		y := pv.rect.y - pv.scroll_y
		for line in lines {
			line_c := strings.clone_to_cstring(line, context.temp_allocator)
			pos := rl.Vector2{pv.rect.x, y}
			rl.DrawTextEx(font, line_c, pos, FONT_SIZE, LINE_SPACING, rl.Color{30, 30, 30, 255})
			y += LINE_HEIGHT
		}
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

wrap_text :: proc(text: string, max_width: f32) -> []string {
	// using temp_allocator so we don't have to manually delete every frame
	// this will be done in the ui run loop with free_all(context.temp_allocator)
	lines := make([dynamic]string, context.temp_allocator)
	words := strings.fields(text, context.temp_allocator)
	current_line := strings.builder_make(context.temp_allocator)

	for word in words {
		candidate: string
		if strings.builder_len(current_line) == 0 {
			candidate = word
		} else {
			candidate = strings.concatenate(
				{strings.to_string(current_line), " ", word},
				context.temp_allocator,
			)
		}

		candidate_c := strings.clone_to_cstring(candidate, context.temp_allocator)
		width := rl.MeasureTextEx(font, candidate_c, FONT_SIZE, LINE_SPACING).x

		if width > max_width && strings.builder_len(current_line) > 0 {
			append(&lines, strings.clone(strings.to_string(current_line), context.temp_allocator))
			strings.builder_reset(&current_line)
			strings.write_string(&current_line, word)
		} else {
			strings.builder_reset(&current_line)
			strings.write_string(&current_line, candidate)
		}
	}

	if strings.builder_len(current_line) > 0 {
		append(&lines, strings.clone(strings.to_string(current_line), context.temp_allocator))
	}

	return lines[:]
}
