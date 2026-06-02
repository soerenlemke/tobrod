package ui

import "core:strings"
import sdl "vendor:sdl3"
import "vendor:sdl3/ttf"

// Global font for text rendering
font: ^ttf.Font = nil

Ui_FontError :: struct {
	message: string,
}

// should be called at the start of the app to make sure fonts are available
ui_fonts_init :: proc(font_path: string) {
	if ttf.Init() == false {
		panic("ttf init failed")
	}

	font_c := strings.clone_to_cstring(font_path)
	font = ttf.OpenFont(font_c, 16)
	if font == nil {
		panic("could not load selected font")
	}
}

ui_fonts_close :: proc() {
	if font != nil {
		ttf.CloseFont(font)
	}
	ttf.Quit()
}

// renders text to sdl texture
ui_fonts_render_text_to_texture :: proc(
	renderer: ^sdl.Renderer,
	text: cstring,
	color: sdl.Color,
) -> ^sdl.Texture {
	surface := ttf.RenderText_Blended(font, text, len(text), color)
	if surface == nil {
		return nil
	}

	texture := sdl.CreateTextureFromSurface(renderer, surface)
	sdl.free(surface)

	sdl.SetTextureBlendMode(texture, sdl.BLENDMODE_BLEND)

	return texture
}
