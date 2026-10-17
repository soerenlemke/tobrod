package ui

import "core:strings"
import rl "vendor:raylib"
import "../dom"
import "../layout"

PageView :: struct {
	rect:           rl.Rectangle,
	bg_color:       rl.Color,
	document:       ^dom.Document,  // owned, see page_view_set_document
	page_layout:    ^layout.Layout, // cached, rebuilt only when the width changes
	scroll_y:       f32,
	content_height: f32,
}

// Synthetic bold: without a bold font face we draw the text a second time,
// shifted by this many pixels. Browsers do the same when a font has no bold.
SYNTHETIC_BOLD_OFFSET :: f32(1)

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

// Takes ownership of doc: the page view destroys it when the next document
// is set or in page_view_destroy.
page_view_set_document :: proc(pv: ^PageView, doc: ^dom.Document) {
	page_view_clear(pv)
	pv.document = doc
	pv.scroll_y = 0
}

// Shows plain text (e.g. an error message) through the same path as HTML.
page_view_set_content :: proc(pv: ^PageView, text: string) {
	doc, err := dom.from_plain_text(text)
	if _, failed := err.?; failed {
		page_view_set_document(pv, nil)
		return
	}
	page_view_set_document(pv, doc)
}

page_view_destroy :: proc(pv: ^PageView) {
	page_view_clear(pv)
}

@(private)
page_view_clear :: proc(pv: ^PageView) {
	if pv.page_layout != nil {
		layout.destroy(pv.page_layout)
		pv.page_layout = nil
	}
	if pv.document != nil {
		dom.destroy(pv.document)
		pv.document = nil
	}
	pv.content_height = 0
}

// Layout is expensive, so it only runs when there is none yet or the width changed.
@(private)
page_view_ensure_layout :: proc(pv: ^PageView) {
	if pv.document == nil {
		return
	}
	if pv.page_layout != nil && pv.page_layout.width == pv.rect.width {
		return
	}
	if pv.page_layout != nil {
		layout.destroy(pv.page_layout)
	}
	pv.page_layout = layout.build(pv.document, pv.rect.width, measure_text)
	pv.content_height = pv.page_layout.height
	clamp_scroll(pv)
}

page_view_render :: proc(pv: ^PageView) {
	page_view_ensure_layout(pv)

	rl.BeginScissorMode(i32(pv.rect.x), i32(pv.rect.y), i32(pv.rect.width), i32(pv.rect.height))
	defer rl.EndScissorMode()

	rl.DrawRectangleRec(pv.rect, pv.bg_color)
	if pv.page_layout == nil {
		return
	}

	for run in pv.page_layout.runs {
		// skip what is outside the visible area
		top := run.y - pv.scroll_y
		if top + run.font_size < 0 || top > pv.rect.height {
			continue
		}

		text_c := strings.clone_to_cstring(run.text, context.temp_allocator)
		pos := rl.Vector2{pv.rect.x + run.x, pv.rect.y + top}
		color := rl.Color(run.color)
		rl.DrawTextEx(font, text_c, pos, run.font_size, 0, color)
		if run.bold {
			rl.DrawTextEx(font, text_c, pos + {SYNTHETIC_BOLD_OFFSET, 0}, run.font_size, 0, color)
		}
	}
}

// The Measure_Text proc for layout: asks raylib how wide the text is.
@(private)
measure_text :: proc(text: string, font_size: f32, bold: bool) -> f32 {
	text_c := strings.clone_to_cstring(text, context.temp_allocator)
	width := rl.MeasureTextEx(font, text_c, font_size, 0).x
	if bold {
		width += SYNTHETIC_BOLD_OFFSET
	}
	return width
}

page_view_handle_resize :: proc(pv: ^PageView, window_width, window_height: i32) {
	pv.rect.width = f32(window_width)
	pv.rect.height = f32(window_height) - ADDRESS_BAR_HEIGHT
	// the layout notices the new width on the next render
}

page_view_handle_scroll :: proc(pv: ^PageView, wheel_y: f32) {
	pv.scroll_y -= wheel_y * PAGE_VIEW_SCROLL_SPEED
	clamp_scroll(pv)
}

// Scrolling stays within the content; no scrolling if it fits into the view.
@(private)
clamp_scroll :: proc(pv: ^PageView) {
	max_scroll := max(pv.content_height - pv.rect.height, 0)
	pv.scroll_y = clamp(pv.scroll_y, 0, max_scroll)
}
