package ui

import "core:strings"
import sdl "vendor:sdl3"

Renderer :: struct {
	sdl_renderer: ^sdl.Renderer,
	text_cache:   map[string]^sdl.Texture,
}

renderer_init :: proc(sdl_renderer: ^sdl.Renderer) -> Renderer {
	return Renderer{sdl_renderer = sdl_renderer, text_cache = make(map[string]^sdl.Texture)}
}

renderer_destroy :: proc(r: ^Renderer) {
	for _, texture in r.text_cache {
		sdl.DestroyTexture(texture)
	}
	delete(r.text_cache)
}

renderer_get_text_texture :: proc(
	r: ^Renderer,
	text: string,
	color: sdl.Color,
	widht_limit: f32,
) -> ^sdl.Texture {
	if texture, ok := r.text_cache[text]; ok {
		return texture
	}

	// if requested text has no cached texture we create one an put it to the text cache
	text_c := strings.clone_to_cstring(text)
	defer delete(text_c)
	texture := fonts_render_text_to_texture(r.sdl_renderer, text_c, color, widht_limit)
	r.text_cache[text] = texture

	return texture
}

renderer_invalidate_text_cache :: proc(r: ^Renderer, text: string) {
	if texture, ok := r.text_cache[text]; ok {
		sdl.DestroyTexture(texture)
		delete_key(&r.text_cache, text)
	}
}
