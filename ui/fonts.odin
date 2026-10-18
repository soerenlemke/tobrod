package ui

import "core:fmt"
import "../layout"
import rl "vendor:raylib"

// Global fonts for text rendering, initialized once via fonts_init.
// font (Inter regular) is also the font of the address bar.
font: rl.Font
page_fonts: [Face]rl.Font

// The font files: Inter (sans-serif) in four styles, JetBrains Mono in two
// (monospace italic is drawn upright).
Face :: enum {
	Regular,
	Bold,
	Italic,
	Bold_Italic,
	Mono,
	Mono_Bold,
}

FONT_PATHS :: [Face]cstring {
	.Regular     = "assets/fonts/Inter_18pt-Regular.ttf",
	.Bold        = "assets/fonts/Inter-Bold.ttf",
	.Italic      = "assets/fonts/Inter-Italic.ttf",
	.Bold_Italic = "assets/fonts/Inter-BoldItalic.ttf",
	.Mono        = "assets/fonts/JetBrainsMono-Regular.ttf",
	.Mono_Bold   = "assets/fonts/JetBrainsMono-Bold.ttf",
}

fonts_init :: proc() -> Maybe(Error) {
	// raylib only bakes the 95 ASCII glyphs into the font texture by default,
	// everything else would be drawn as '?'. So we pass the codepoints we want.
	codepoints := font_codepoints()
	defer delete(codepoints)

	paths := FONT_PATHS
	for face in Face {
		ok: bool
		if page_fonts[face], ok = load_font(paths[face], codepoints[:]); !ok {
			for loaded in Face.Regular ..< face {
				rl.UnloadFont(page_fonts[loaded])
			}
			return Error{message = fmt.tprintf("could not load font %s", paths[face])}
		}
	}
	font = page_fonts[.Regular]
	return nil
}

// The raylib font for a piece of text of the page.
font_for :: proc(f: layout.Font) -> rl.Font {
	if f.mono {
		return page_fonts[.Mono_Bold if f.bold else .Mono]
	}
	switch {
	case f.bold && f.italic:
		return page_fonts[.Bold_Italic]
	case f.bold:
		return page_fonts[.Bold]
	case f.italic:
		return page_fonts[.Italic]
	}
	return page_fonts[.Regular]
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
	// ▲ (the vote arrow of Hacker News), and ✓ ⌄ for checkboxes and selects
	append(&codepoints, 0x25E6, 0x25AA, 0x25B6, 0x25BC, 0x25B2, 0x2713, 0x2304)
	return codepoints
}

fonts_close :: proc() {
	for f in page_fonts {
		rl.UnloadFont(f)
	}
}
