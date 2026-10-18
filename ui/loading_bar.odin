package ui

import "core:math"
import rl "vendor:raylib"

// A thin bar at the bottom of the address bar while a page loads. We don't know
// how long loading takes, so it's "indeterminate": a segment that keeps sliding
// from left to right. It moves because the ui keeps drawing frames while the
// worker thread loads – with blocking loads this was impossible.

LOADING_BAR_HEIGHT :: f32(3)
LOADING_BAR_COLOR :: rl.Color{66, 133, 244, 255} // same blue as the focused address bar

@(private = "file")
SEGMENT_FRACTION :: f32(0.3) // segment width relative to the window
@(private = "file")
SECONDS_PER_PASS :: f64(1.2)

loading_bar_render :: proc(width: f32) {
	segment := width * SEGMENT_FRACTION
	// progress 0..1 within the current pass, from fully left of the window
	// to fully right of it
	progress := f32(math.mod(rl.GetTime(), SECONDS_PER_PASS) / SECONDS_PER_PASS)
	x := -segment + progress * (width + segment)
	y := f32(CHROME_HEIGHT) - LOADING_BAR_HEIGHT
	rl.DrawRectangleRec({x, y, segment, LOADING_BAR_HEIGHT}, LOADING_BAR_COLOR)
}
