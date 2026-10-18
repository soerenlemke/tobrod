package ui

import "core:math"
import "core:strings"
import rl "vendor:raylib"

// The tabs at the top of the window: a title per tab (or its address while
// it has none), a close button, and "+" for a new tab. The active tab has
// the color of the address bar below, so they look like one piece.
//
// The ui doesn't change the tabs itself: clicks and shortcuts go to the
// browser as a Tab_Event, and the browser calls tab_add / tab_remove /
// tab_select, because each tab also has a history and a loader there.
//
// Shortcuts like in other browsers: Ctrl+T new tab, Ctrl+W close,
// Ctrl+Tab / Ctrl+Shift+Tab (and Ctrl+PageDown / PageUp) next / previous,
// Ctrl+1..8 that tab, Ctrl+9 the last one. A middle click closes a tab.

Tab_Event :: struct {
	kind:  Tab_Event_Kind,
	index: int, // the tab to select or close
}

Tab_Event_Kind :: enum {
	New,
	Select,
	Close,
}

@(private = "file")
TAB_MAX_WIDTH :: f32(220)
@(private = "file")
TAB_MIN_WIDTH :: f32(48)
@(private = "file")
TAB_GAP :: f32(2)
@(private = "file")
TAB_LEFT :: f32(6)
@(private = "file")
TAB_TOP :: f32(5) // the tabs hang from the top, open towards the address bar
@(private = "file")
NEW_TAB_SIZE :: f32(24)
@(private = "file")
CLOSE_SIZE :: f32(16)
@(private = "file")
TITLE_SIZE :: f32(13)

@(private = "file")
STRIP_COLOR :: rl.Color{218, 218, 222, 255}
@(private = "file")
TAB_COLOR :: rl.Color{205, 205, 210, 255}
@(private = "file")
TAB_HOVER_COLOR :: rl.Color{228, 228, 232, 255}
@(private = "file")
ACTIVE_TAB_COLOR :: rl.Color{240, 240, 240, 255} // = the address bar's background
@(private = "file")
TEXT_COLOR :: rl.Color{40, 40, 40, 255}
@(private = "file")
ICON_COLOR :: rl.Color{80, 80, 80, 255}
@(private = "file")
SPINNER_COLOR :: rl.Color{66, 133, 244, 255}

// Tabs share the width (minus the "+" button), each at most TAB_MAX_WIDTH.
@(private = "file")
tab_rect :: proc(ui: ^MainWindow, index: int) -> rl.Rectangle {
	n := f32(len(ui.tabs))
	available := f32(rl.GetScreenWidth()) - TAB_LEFT - NEW_TAB_SIZE - 3 * TAB_GAP - TAB_LEFT
	width := clamp((available - (n - 1) * TAB_GAP) / n, TAB_MIN_WIDTH, TAB_MAX_WIDTH)
	return {TAB_LEFT + f32(index) * (width + TAB_GAP), TAB_TOP, width, TAB_BAR_HEIGHT - TAB_TOP}
}

@(private = "file")
close_rect :: proc(tab: rl.Rectangle) -> rl.Rectangle {
	return {tab.x + tab.width - CLOSE_SIZE - 6, tab.y + (tab.height - CLOSE_SIZE) / 2, CLOSE_SIZE, CLOSE_SIZE}
}

@(private = "file")
new_tab_rect :: proc(ui: ^MainWindow) -> rl.Rectangle {
	last := tab_rect(ui, len(ui.tabs) - 1)
	return {last.x + last.width + 3 * TAB_GAP, TAB_TOP + (TAB_BAR_HEIGHT - TAB_TOP - NEW_TAB_SIZE) / 2, NEW_TAB_SIZE, NEW_TAB_SIZE}
}

tab_bar_handle_input :: proc(ui: ^MainWindow) {
	if ui.on_tab == nil || len(ui.tabs) == 0 {
		return
	}
	send :: proc(ui: ^MainWindow, kind: Tab_Event_Kind, index := 0) {
		ui.on_tab({kind, index}, ui.on_tab_ctx)
	}

	mouse := rl.GetMousePosition()
	left, middle := rl.IsMouseButtonPressed(.LEFT), rl.IsMouseButtonPressed(.MIDDLE)
	if (left || middle) && mouse.y < TAB_BAR_HEIGHT {
		if left && rl.CheckCollisionPointRec(mouse, new_tab_rect(ui)) {
			send(ui, .New)
			return
		}
		for i in 0 ..< len(ui.tabs) {
			rect := tab_rect(ui, i)
			if !rl.CheckCollisionPointRec(mouse, rect) {
				continue
			}
			if middle || rl.CheckCollisionPointRec(mouse, close_rect(rect)) {
				send(ui, .Close, i)
			} else if i != ui.active {
				send(ui, .Select, i)
			}
			return
		}
	}

	ctrl := rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL)
	shift := rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT)
	if !ctrl {
		return
	}
	n := len(ui.tabs)
	switch {
	case rl.IsKeyPressed(.T):
		send(ui, .New)
	case rl.IsKeyPressed(.W):
		send(ui, .Close, ui.active)
	case (rl.IsKeyPressed(.TAB) && !shift) || rl.IsKeyPressed(.PAGE_DOWN):
		send(ui, .Select, (ui.active + 1) % n)
	case (rl.IsKeyPressed(.TAB) && shift) || rl.IsKeyPressed(.PAGE_UP):
		send(ui, .Select, (ui.active + n - 1) % n)
	case rl.IsKeyPressed(.NINE):
		send(ui, .Select, n - 1)
	case:
		for key, i in ([8]rl.KeyboardKey{.ONE, .TWO, .THREE, .FOUR, .FIVE, .SIX, .SEVEN, .EIGHT}) {
			if rl.IsKeyPressed(key) && i < n {
				send(ui, .Select, i)
				break
			}
		}
	}
}

tab_bar_render :: proc(ui: ^MainWindow) {
	width := f32(rl.GetScreenWidth())
	rl.DrawRectangleRec({0, 0, width, TAB_BAR_HEIGHT}, STRIP_COLOR)
	mouse := rl.GetMousePosition()

	for tab, i in ui.tabs {
		rect := tab_rect(ui, i)
		hover := rl.CheckCollisionPointRec(mouse, rect)
		color := ACTIVE_TAB_COLOR if i == ui.active else (TAB_HOVER_COLOR if hover else TAB_COLOR)
		// rounded at the top only: a rounded rectangle plus a square bottom half
		rl.DrawRectangleRounded(rect, 0.35, 6, color)
		rl.DrawRectangleRec({rect.x, rect.y + rect.height / 2, rect.width, rect.height / 2}, color)

		// a spinner while the tab loads
		text_left := rect.x + 10
		if tab.loading {
			center := rl.Vector2{rect.x + 16, rect.y + rect.height / 2}
			start := f32(math.mod(rl.GetTime(), 1.0) * 360)
			rl.DrawRing(center, 4.5, 6.5, start, start + 270, 24, SPINNER_COLOR)
			text_left = rect.x + 28
		}

		// the title, or the address while there is none, cut to fit
		title := strings.to_string(tab.title)
		if title == "" {
			title = strings.to_string(tab.address)
		}
		if title == "" {
			title = "New Tab"
		}
		close := close_rect(rect)
		text_c := fit_text(title, close.x - 4 - text_left)
		size := rl.MeasureTextEx(font, text_c, TITLE_SIZE, 0)
		rl.DrawTextEx(font, text_c, {text_left, rect.y + (rect.height - size.y) / 2}, TITLE_SIZE, 0, TEXT_COLOR)

		// close button: a cross, highlighted under the mouse
		if rl.CheckCollisionPointRec(mouse, close) {
			rl.DrawRectangleRounded(close, 0.5, 6, rl.Color{0, 0, 0, 30})
		}
		c := rl.Vector2{close.x + close.width / 2, close.y + close.height / 2}
		d :: f32(3.5)
		rl.DrawLineEx(c + {-d, -d}, c + {d, d}, 1.5, ICON_COLOR)
		rl.DrawLineEx(c + {-d, d}, c + {d, -d}, 1.5, ICON_COLOR)
	}

	// "+"
	plus := new_tab_rect(ui)
	if rl.CheckCollisionPointRec(mouse, plus) {
		rl.DrawRectangleRounded(plus, 0.3, 6, TAB_HOVER_COLOR)
	}
	c := rl.Vector2{plus.x + plus.width / 2, plus.y + plus.height / 2}
	rl.DrawLineEx(c + {-6, 0}, c + {6, 0}, 2, ICON_COLOR)
	rl.DrawLineEx(c + {0, -6}, c + {0, 6}, 2, ICON_COLOR)
}

// The text, shortened with "…" until it fits into width.
@(private = "file")
fit_text :: proc(text: string, width: f32) -> cstring {
	full := strings.clone_to_cstring(text, context.temp_allocator)
	if rl.MeasureTextEx(font, full, TITLE_SIZE, 0).x <= width {
		return full
	}
	shortened :: proc(text: string, keep: int) -> cstring {
		// the first keep characters (runes, not bytes)
		end := len(text)
		count := 0
		for _, i in text {
			if count == keep {
				end = i
				break
			}
			count += 1
		}
		cut := text[:end]
		return strings.clone_to_cstring(strings.concatenate({strings.trim_right_space(cut), "…"}, context.temp_allocator), context.temp_allocator)
	}
	// the most characters that fit, by bisection (this runs every frame)
	lo, hi := 0, strings.rune_count(text) - 1
	for lo < hi {
		mid := (lo + hi + 1) / 2
		if rl.MeasureTextEx(font, shortened(text, mid), TITLE_SIZE, 0).x <= width {
			lo = mid
		} else {
			hi = mid - 1
		}
	}
	return shortened(text, lo)
}
