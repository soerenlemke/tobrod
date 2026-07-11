package ui

import "core:strings"
import rl "vendor:raylib"

// Global font for text rendering, initialized once via fonts_init
font: rl.Font

fonts_init :: proc(font_path: string) -> Maybe(Error) {
	font_c := strings.clone_to_cstring(font_path)
	defer delete(font_c)

	font = rl.LoadFontEx(font_c, 32, nil, 0)
	if font.texture.id == 0 {
		return Error{message = "could not load font"}
	}

	return nil
}

fonts_close :: proc() {
	rl.UnloadFont(font)
}
