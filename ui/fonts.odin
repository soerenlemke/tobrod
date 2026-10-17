package ui

import "core:strings"
import rl "vendor:raylib"

// Global font for text rendering, initialized once via fonts_init
font: rl.Font

fonts_init :: proc(font_path: string) -> Maybe(Error) {
	font_c := strings.clone_to_cstring(font_path)
	defer delete(font_c)

	// raylib only bakes the 95 ASCII glyphs into the font texture by default,
	// everything else would be drawn as '?'. So we pass the codepoints we want.
	codepoints := font_codepoints()
	defer delete(codepoints)

	font = rl.LoadFontEx(font_c, FONT_LOAD_SIZE, raw_data(codepoints), i32(len(codepoints)))
	if font.texture.id == 0 {
		return Error{message = "could not load font"}
	}
	// Text is mostly drawn smaller than it was rasterized. Mipmaps + trilinear
	// filtering keep it smooth instead of blocky when scaled down.
	rl.GenTextureMipmaps(&font.texture)
	rl.SetTextureFilter(font.texture, .TRILINEAR)

	return nil
}

// ASCII, Latin-1 (umlauts, accents, ß) and common typographic characters.
// Fixed set for now; loading glyphs on demand would cover any text.
@(private)
font_codepoints :: proc() -> [dynamic]rune {
	codepoints: [dynamic]rune
	for r in rune(0x20) ..= 0x7E {
		append(&codepoints, r)
	}
	for r in rune(0xA0) ..= 0xFF {
		append(&codepoints, r)
	}
	// – — ‘ ’ ‚ “ ” „ • … €
	append(&codepoints, 0x2013, 0x2014, 0x2018, 0x2019, 0x201A, 0x201C, 0x201D, 0x201E, 0x2022, 0x2026, 0x20AC)
	return codepoints
}

fonts_close :: proc() {
	rl.UnloadFont(font)
}
