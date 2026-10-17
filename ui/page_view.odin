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

// Layout is expensive, so it only runs when there is none yet or the size of
// the page view changed (the width wraps the text, the height resolves vh).
@(private)
page_view_ensure_layout :: proc(pv: ^PageView) {
	if pv.document == nil {
		return
	}
	viewport := [2]f32{pv.rect.width, pv.rect.height}
	if pv.page_layout != nil && pv.page_layout.viewport == viewport {
		return
	}
	if pv.page_layout != nil {
		layout.destroy(pv.page_layout)
	}
	pv.page_layout = layout.build(pv.document, viewport, measure_text)
	pv.content_height = pv.page_layout.height
	clamp_scroll(pv)
}

page_view_render :: proc(pv: ^PageView) {
	page_view_ensure_layout(pv)

	rl.BeginScissorMode(i32(pv.rect.x), i32(pv.rect.y), i32(pv.rect.width), i32(pv.rect.height))
	defer rl.EndScissorMode()

	if pv.page_layout == nil {
		rl.DrawRectangleRec(pv.rect, pv.bg_color)
		return
	}

	// display list order: page background, boxes (parents first), text
	rl.DrawRectangleRec(pv.rect, rl.Color(pv.page_layout.background))
	for box in pv.page_layout.boxes {
		top := box.y - pv.scroll_y
		if top + box.height < 0 || top > pv.rect.height {
			continue
		}
		x, y := pv.rect.x + box.x, pv.rect.y + top
		if box.color[3] > 0 {
			rl.DrawRectangleRec({x, y, box.width, box.height}, rl.Color(box.color))
		}
		// borders on top of the background: top and bottom over the full width,
		// left and right in between
		bt, br, bb, bl := box.border[.Top], box.border[.Right], box.border[.Bottom], box.border[.Left]
		rl.DrawRectangleRec({x, y, box.width, bt}, rl.Color(box.border_color[.Top]))
		rl.DrawRectangleRec({x, y + box.height - bb, box.width, bb}, rl.Color(box.border_color[.Bottom]))
		rl.DrawRectangleRec({x, y + bt, bl, box.height - bt - bb}, rl.Color(box.border_color[.Left]))
		rl.DrawRectangleRec({x + box.width - br, y + bt, br, box.height - bt - bb}, rl.Color(box.border_color[.Right]))
	}

	// images: decoding comes in a later step, until then all are placeholders
	for image in pv.page_layout.images {
		top := image.y - pv.scroll_y
		if top + image.height < 0 || top > pv.rect.height {
			continue
		}
		draw_image_placeholder({pv.rect.x + image.x, pv.rect.y + top, image.width, image.height})
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
		rl.DrawTextEx(font_for(run.bold), text_c, pos, run.font_size, 0, color)
	}
}

// A light grey box with a border where an image will be (or failed to load).
@(private)
draw_image_placeholder :: proc(rect: rl.Rectangle) {
	rl.DrawRectangleRec(rect, rl.Color{235, 235, 235, 255})
	rl.DrawRectangleLinesEx(rect, 1, rl.Color{190, 190, 190, 255})
}

// The Measure_Text proc for layout: asks raylib how wide the text is.
@(private)
measure_text :: proc(text: string, font_size: f32, bold: bool) -> f32 {
	text_c := strings.clone_to_cstring(text, context.temp_allocator)
	return rl.MeasureTextEx(font_for(bold), text_c, font_size, 0).x
}

// Hand cursor over links, a left click on a link goes to on_link_click.
page_view_handle_mouse :: proc(ui: ^MainWindow, pv: ^PageView) {
	if pv.page_layout == nil {
		return
	}
	mouse := rl.GetMousePosition()
	if !rl.CheckCollisionPointRec(mouse, pv.rect) {
		return
	}

	// window coordinates -> page coordinates
	x := mouse.x - pv.rect.x
	y := mouse.y - pv.rect.y + pv.scroll_y
	link, on_link := layout.link_at(pv.page_layout, x, y)

	rl.SetMouseCursor(.POINTING_HAND if on_link else .DEFAULT)

	if on_link && rl.IsMouseButtonPressed(.LEFT) && ui.on_link_click != nil {
		// The callback usually loads a new page, which destroys the layout the
		// link string lives in. So hand over a copy that lives until frame end.
		href := strings.clone(link, context.temp_allocator)
		ui.on_link_click(href, ui.on_link_click_ctx)
	}
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
