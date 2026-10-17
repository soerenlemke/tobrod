package ui

import "core:strings"
import rl "vendor:raylib"

// The decoded images of the current page, as GPU textures, by src as written
// in the page (the same key the layout uses). Decoding happens here on the ui
// thread: textures can only be created on the thread that owns the window.

// Takes the downloaded bytes of an image, decodes them and makes the layout
// use the natural size from now on. Undecodable data (unknown format, an HTML
// error page, ...) is ignored: the image stays empty once the page is loaded.
page_view_add_image :: proc(pv: ^PageView, src, url, content_type: string, data: []u8) {
	if pv.document == nil || src in pv.images || len(data) == 0 {
		return
	}
	file_type, ok := image_file_type(content_type, url)
	if !ok {
		return
	}

	image := rl.LoadImageFromMemory(file_type, raw_data(data), i32(len(data)))
	if !rl.IsImageValid(image) {
		return
	}
	defer rl.UnloadImage(image) // the pixels live on the GPU after this

	texture := rl.LoadTextureFromImage(image)
	if texture.id == 0 {
		return
	}
	// images are drawn scaled most of the time
	rl.SetTextureFilter(texture, .BILINEAR)

	key := strings.clone(src)
	pv.images[key] = texture
	pv.image_sizes[key] = {f32(image.width), f32(image.height)}

	// the image may have a different size than its placeholder: lay out again
	page_view_invalidate_layout(pv)
}

@(private)
page_view_clear_images :: proc(pv: ^PageView) {
	for key, texture in pv.images {
		rl.UnloadTexture(texture)
		delete(key) // image_sizes shares the keys
	}
	clear(&pv.images)
	clear(&pv.image_sizes)
}

// raylib picks the decoder by file extension. Prefer the content type,
// fall back to the extension of the URL.
@(private)
image_file_type :: proc(content_type, url: string) -> (file_type: cstring, ok: bool) {
	switch {
	case strings.has_prefix(content_type, "image/png"):
		return ".png", true
	case strings.has_prefix(content_type, "image/jpeg"):
		return ".jpg", true
	case strings.has_prefix(content_type, "image/gif"):
		return ".gif", true
	case strings.has_prefix(content_type, "image/bmp"):
		return ".bmp", true
	case strings.has_prefix(content_type, "image/qoi"):
		return ".qoi", true
	}

	path := url
	if i := strings.index_any(path, "?#"); i >= 0 {
		path = path[:i]
	}
	lower := strings.to_lower(path, context.temp_allocator)
	for ext in ([]cstring{".png", ".jpg", ".jpeg", ".gif", ".bmp", ".qoi"}) {
		if strings.has_suffix(lower, string(ext)) {
			return ".jpg" if ext == ".jpeg" else ext, true
		}
	}
	return nil, false
}
