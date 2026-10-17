package ui

// ui wide constants
ADDRESS_BAR_HEIGHT :: 36
PAGE_VIEW_SCROLL_SPEED :: f32(30)

// The font is rasterized once at this size and scaled down when drawn;
// large enough that headings stay sharp.
FONT_LOAD_SIZE :: 64

// Frames to render before a --screenshot is taken, to give the window
// a moment to settle (size, focus) before it is captured.
SCREENSHOT_AFTER_FRAMES :: 3
