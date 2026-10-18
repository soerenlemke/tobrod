package ui

import "core:math"
import rl "vendor:raylib"

// Back, forward and reload on the left of the address bar. The icons are
// drawn with lines and a ring instead of font glyphs (Inter has no ↻ and
// shapes stay crisp at any size).

Nav_Action :: enum {
	Back,
	Forward,
	Reload,
	Stop, // takes the place of Reload while a page is loading
}

NavButtons :: struct {
	can_back:    bool,
	can_forward: bool,
	loading:     bool,
}

NAV_BUTTON_SIZE :: f32(24)
NAV_BUTTON_GAP :: f32(2)
NAV_BUTTONS_LEFT :: f32(6)
NAV_BUTTONS_WIDTH :: 3 * NAV_BUTTON_SIZE + 2 * NAV_BUTTON_GAP

@(private = "file")
ICON_COLOR :: rl.Color{70, 70, 70, 255}
@(private = "file")
ICON_DISABLED_COLOR :: rl.Color{190, 190, 190, 255}
@(private = "file")
HOVER_COLOR :: rl.Color{220, 220, 220, 255}

// The buttons currently shown, left to right.
@(private = "file")
visible_buttons :: proc(nav: ^NavButtons) -> [3]Nav_Action {
	return {.Back, .Forward, .Stop if nav.loading else .Reload}
}

nav_button_rect :: proc(action: Nav_Action) -> rl.Rectangle {
	slot := min(int(action), int(Nav_Action.Reload)) // Stop shares the slot of Reload
	x := NAV_BUTTONS_LEFT + f32(slot) * (NAV_BUTTON_SIZE + NAV_BUTTON_GAP)
	y := (ADDRESS_BAR_HEIGHT - NAV_BUTTON_SIZE) / 2
	return {x, y, NAV_BUTTON_SIZE, NAV_BUTTON_SIZE}
}

@(private = "file")
nav_button_enabled :: proc(nav: ^NavButtons, action: Nav_Action) -> bool {
	switch action {
	case .Back:
		return nav.can_back
	case .Forward:
		return nav.can_forward
	case .Reload, .Stop:
		return true
	}
	return false
}

// Clicks on the buttons and keyboard shortcuts: Alt+Left / Alt+Right like in
// every browser, F5 or Ctrl+R to reload, Escape to stop loading.
nav_buttons_handle_input :: proc(ui: ^MainWindow, nav: ^NavButtons) {
	if ui.on_navigate == nil {
		return
	}

	if rl.IsMouseButtonPressed(.LEFT) {
		mouse := rl.GetMousePosition()
		for action in visible_buttons(nav) {
			if nav_button_enabled(nav, action) && rl.CheckCollisionPointRec(mouse, nav_button_rect(action)) {
				ui.on_navigate(action, ui.on_navigate_ctx)
				return
			}
		}
	}

	alt := rl.IsKeyDown(.LEFT_ALT) || rl.IsKeyDown(.RIGHT_ALT)
	ctrl := rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL)
	switch {
	case alt && rl.IsKeyPressed(.LEFT) && nav.can_back:
		ui.on_navigate(.Back, ui.on_navigate_ctx)
	case alt && rl.IsKeyPressed(.RIGHT) && nav.can_forward:
		ui.on_navigate(.Forward, ui.on_navigate_ctx)
	case rl.IsKeyPressed(.F5) || (ctrl && rl.IsKeyPressed(.R)):
		ui.on_navigate(.Reload, ui.on_navigate_ctx)
	case nav.loading && rl.IsKeyPressed(.ESCAPE) && !ui.address_bar.focused:
		// with a focused address bar, Escape only leaves the text field
		ui.on_navigate(.Stop, ui.on_navigate_ctx)
	}
}

nav_buttons_render :: proc(nav: ^NavButtons) {
	mouse := rl.GetMousePosition()
	for action in visible_buttons(nav) {
		rect := nav_button_rect(action)
		enabled := nav_button_enabled(nav, action)
		if enabled && rl.CheckCollisionPointRec(mouse, rect) {
			rl.DrawRectangleRounded(rect, 0.3, 6, HOVER_COLOR)
		}

		color := ICON_COLOR if enabled else ICON_DISABLED_COLOR
		center := rl.Vector2{rect.x + rect.width / 2, rect.y + rect.height / 2}
		switch action {
		case .Back:
			draw_arrow(center, -1, color)
		case .Forward:
			draw_arrow(center, 1, color)
		case .Reload:
			draw_reload(center, color)
		case .Stop:
			draw_cross(center, color)
		}
	}
}

// Horizontal arrow: a shaft and a chevron; direction -1 = left, 1 = right.
@(private = "file")
draw_arrow :: proc(center: rl.Vector2, direction: f32, color: rl.Color) {
	thickness :: 2
	tip := center + {6 * direction, 0}
	rl.DrawLineEx(center - {6 * direction, 0}, tip, thickness, color)
	rl.DrawLineEx(tip, tip + {-5 * direction, -5}, thickness, color)
	rl.DrawLineEx(tip, tip + {-5 * direction, 5}, thickness, color)
}

// Stop: a cross like ✕.
@(private = "file")
draw_cross :: proc(center: rl.Vector2, color: rl.Color) {
	thickness :: 2
	d :: f32(5)
	rl.DrawLineEx(center + {-d, -d}, center + {d, d}, thickness, color)
	rl.DrawLineEx(center + {-d, d}, center + {d, -d}, thickness, color)
}

// Circular arrow: an open ring with an arrow head at its end.
@(private = "file")
draw_reload :: proc(center: rl.Vector2, color: rl.Color) {
	radius :: f32(6)
	// raylib angles are in degrees, 0 = right, growing clockwise (y points down).
	// The ring runs clockwise from START to END, the gap is at the top right.
	START :: f32(20)
	END :: f32(290)
	rl.DrawRing(center, radius - 1, radius + 1, START, END, 32, color)

	// arrow head at the end of the ring, pointing on in clockwise direction
	angle := END * rl.DEG2RAD
	radial := rl.Vector2{math.cos(angle), math.sin(angle)}
	tangent := rl.Vector2{-radial.y, radial.x} // radial turned by 90°: the way the ring goes
	end := center + radial * radius
	draw_triangle_any_order(end + tangent * 4, end + radial * 4, end - radial * 4, color)
}

// raylib skips triangles whose corners are not counter-clockwise on screen
// (backface culling), so sort them first. Also used for rounded boxes.
@(private)
draw_triangle_any_order :: proc(a, b, c: rl.Vector2, color: rl.Color) {
	cross := (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
	if cross < 0 {
		rl.DrawTriangle(a, b, c, color)
	} else {
		rl.DrawTriangle(a, c, b, color)
	}
}
