package ui

import "core:math"
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
	images:         map[string]rl.Texture2D, // decoded images of the document, see page_images.odin
	image_sizes:    layout.Image_Sizes,      // their natural sizes, for the layout
	loading:        bool,                    // the page or its images are still loading (set_loading)
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
	delete(pv.images)
	delete(pv.image_sizes)
}

// Drops the cached layout; the next render builds a new one.
@(private)
page_view_invalidate_layout :: proc(pv: ^PageView) {
	if pv.page_layout != nil {
		layout.destroy(pv.page_layout)
		pv.page_layout = nil
	}
}

@(private)
page_view_clear :: proc(pv: ^PageView) {
	page_view_invalidate_layout(pv)
	page_view_clear_images(pv)
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
	pv.page_layout = layout.build(pv.document, viewport, measure_text, pv.image_sizes)
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

	// paint order: the page background, then layer by layer (the normal
	// flow, positioned elements by z-index, see layout/stacking.odin) its
	// boxes (parents first), images and text; then the same for the fixed
	// elements, which don't scroll
	rl.DrawRectangleRec(pv.rect, rl.Color(pv.page_layout.background))
	l := pv.page_layout
	for layer in l.layers {
		draw_display_list(pv, l.boxes[layer.boxes[0]:layer.boxes[1]], l.images[layer.images[0]:layer.images[1]], l.runs[layer.runs[0]:layer.runs[1]], pv.scroll_y)
	}
	for layer in l.fixed.layers {
		draw_display_list(pv, l.fixed.boxes[layer.boxes[0]:layer.boxes[1]], l.fixed.images[layer.images[0]:layer.images[1]], l.fixed.runs[layer.runs[0]:layer.runs[1]], 0)
	}
}

// Draws boxes, images and runs; scroll_y is how far they are scrolled up.
// Items of an overflow: hidden box are only drawn inside its clip rectangle
// (raylib's scissor mode, switched only when the clip changes).
@(private)
draw_display_list :: proc(pv: ^PageView, boxes: []layout.Box, images: []layout.Image_Item, runs: []layout.Text_Run, scroll_y: f32) {
	current: layout.Clip = 0
	defer set_clip(pv, 0, scroll_y, &current) // back to the whole page view

	for box in boxes {
		top := box.y - scroll_y
		if top + box.height < 0 || top > pv.rect.height {
			continue
		}
		set_clip(pv, box.clip, scroll_y, &current)
		x, y := pv.rect.x + box.x, pv.rect.y + top
		if box.radius != {} {
			draw_rounded_box(x, y, box)
			continue
		}
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

	// images: the decoded texture scaled to the layout size, or a placeholder
	// while the page is loading. Once everything is loaded, an image without
	// a texture failed (or has a format we can't decode, like WebP): like a
	// browser, we leave its place empty instead of covering the page with grey.
	for image in images {
		top := image.y - scroll_y
		if top + image.height < 0 || top > pv.rect.height {
			continue
		}
		set_clip(pv, image.clip, scroll_y, &current)
		dest := rl.Rectangle{pv.rect.x + image.x, pv.rect.y + top, image.width, image.height}
		if texture, ok := pv.images[image.src]; ok {
			source := rl.Rectangle{0, 0, f32(texture.width), f32(texture.height)}
			rl.DrawTexturePro(texture, source, dest, {0, 0}, 0, rl.WHITE)
		} else if pv.loading {
			draw_image_placeholder(dest)
		}
	}

	for run in runs {
		// skip what is outside the visible area
		top := run.y - scroll_y
		if top + run.font_size < 0 || top > pv.rect.height {
			continue
		}

		set_clip(pv, run.clip, scroll_y, &current)
		text_c := strings.clone_to_cstring(run.text, context.temp_allocator)
		pos := rl.Vector2{pv.rect.x + run.x, pv.rect.y + top}
		color := rl.Color(run.color)
		rl.DrawTextEx(font_for(run.font), text_c, pos, run.font_size, run.letter_spacing, color)
		draw_decoration(run, pos)
	}
}

// Underline, overline and line-through of a run whose top left is at pos.
// The heights are fractions of the font size that fit Inter: its baseline is
// at about 0.8 of the size, the middle of lowercase letters at about 0.53.
@(private)
draw_decoration :: proc(run: layout.Text_Run, pos: rl.Vector2) {
	d := run.decoration
	if d.lines == {} {
		return
	}
	thickness := max(1, math.round(run.font_size / 14))
	color := rl.Color(d.color)
	x, width := pos.x - run.decoration_lead, run.width + run.decoration_lead
	line :: proc(x, width, y, thickness: f32, color: rl.Color) {
		rl.DrawRectangleRec({x, math.round(y), width, thickness}, color)
	}
	if .Underline in d.lines {
		line(x, width, pos.y + run.font_size * 0.9, thickness, color)
	}
	if .Overline in d.lines {
		line(x, width, pos.y + run.font_size * 0.04, thickness, color)
	}
	if .Line_Through in d.lines {
		line(x, width, pos.y + run.font_size * 0.53, thickness, color)
	}
}

// Limits drawing to the clip rectangle (and always to the page view).
@(private)
set_clip :: proc(pv: ^PageView, clip: layout.Clip, scroll_y: f32, current: ^layout.Clip) {
	if clip == current^ {
		return
	}
	current^ = clip
	x0, y0 := pv.rect.x, pv.rect.y
	x1, y1 := x0 + pv.rect.width, y0 + pv.rect.height
	if r, ok := layout.clip_rect(pv.page_layout, clip); ok {
		x0 = max(x0, pv.rect.x + r.x)
		y0 = max(y0, pv.rect.y + r.y - scroll_y)
		x1 = min(x1, pv.rect.x + r.x + r.width)
		y1 = min(y1, pv.rect.y + r.y + r.height - scroll_y)
	}
	rl.EndScissorMode()
	rl.BeginScissorMode(i32(x0), i32(y0), i32(max(x1 - x0, 0)), i32(max(y1 - y0, 0)))
}

// A light grey box with a border where an image will be.
@(private)
draw_image_placeholder :: proc(rect: rl.Rectangle) {
	rl.DrawRectangleRec(rect, rl.Color{235, 235, 235, 255})
	rl.DrawRectangleLinesEx(rect, 1, rl.Color{190, 190, 190, 255})
}

// The Measure_Text proc for layout: asks raylib how wide the text is.
@(private)
measure_text :: proc(text: string, font_size: f32, font: layout.Font) -> f32 {
	text_c := strings.clone_to_cstring(text, context.temp_allocator)
	return rl.MeasureTextEx(font_for(font), text_c, font_size, 0).x
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
	link, on_link := layout.link_at(pv.page_layout, x, y, pv.scroll_y)

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

page_view_scroll_to :: proc(pv: ^PageView, y: f32) {
	pv.scroll_y = y
	clamp_scroll(pv)
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
