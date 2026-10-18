package ui

import rl "vendor:raylib"

// Global fonts for text rendering, initialized once via fonts_init
font: rl.Font
font_bold: rl.Font

FONT_REGULAR_PATH :: "assets/fonts/Inter_18pt-Regular.ttf"
FONT_BOLD_PATH :: "assets/fonts/Inter-Bold.ttf"

fonts_init :: proc() -> Maybe(Error) {
	// raylib only bakes the 95 ASCII glyphs into the font texture by default,
	// everything else would be drawn as '?'. So we pass the codepoints we want.
	codepoints := font_codepoints()
	defer delete(codepoints)

	ok: bool
	if font, ok = load_font(FONT_REGULAR_PATH, codepoints[:]); !ok {
		return Error{message = "could not load font " + FONT_REGULAR_PATH}
	}
	if font_bold, ok = load_font(FONT_BOLD_PATH, codepoints[:]); !ok {
		rl.UnloadFont(font)
		return Error{message = "could not load font " + FONT_BOLD_PATH}
	}
	return nil
}

// Regular or bold font for a piece of text.
font_for :: proc(bold: bool) -> rl.Font {
	return font_bold if bold else font
}

@(private)
load_font :: proc(path: cstring, codepoints: []rune) -> (rl.Font, bool) {
	f := rl.LoadFontEx(path, FONT_LOAD_SIZE, raw_data(codepoints), i32(len(codepoints)))
	if f.texture.id == 0 {
		return f, false
	}
	// raylib gives empty glyphs no advance, except the space: the no-break
	// space (&nbsp;) would have no width
	nbsp := rl.GetGlyphIndex(f, 0xA0)
	if f.glyphs[nbsp].value == 0xA0 {
		f.glyphs[nbsp].advanceX = f.glyphs[rl.GetGlyphIndex(f, ' ')].advanceX
	}
	// Text is mostly drawn smaller than it was rasterized. Mipmaps + trilinear
	// filtering keep it smooth instead of blocky when scaled down.
	rl.GenTextureMipmaps(&f.texture)
	rl.SetTextureFilter(f.texture, .TRILINEAR)
	return f, true
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
	// list markers for list-style circle and square: ◦ ▪, of <summary>: ▶ ▼,
	// and ▲ (the vote arrow of Hacker News)
	append(&codepoints, 0x25E6, 0x25AA, 0x25B6, 0x25BC, 0x25B2)
	return codepoints
}

fonts_close :: proc() {
	rl.UnloadFont(font)
	rl.UnloadFont(font_bold)
}
