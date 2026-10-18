package ui

// ui wide constants
TAB_BAR_HEIGHT :: 32     // the tabs, at the very top (tab_bar.odin)
ADDRESS_BAR_HEIGHT :: 36 // navigation buttons and address bar, below the tabs
CHROME_HEIGHT :: TAB_BAR_HEIGHT + ADDRESS_BAR_HEIGHT // everything above the page
PAGE_VIEW_SCROLL_SPEED :: f32(30)

// The font is rasterized once at this size and scaled down when drawn;
// large enough that headings stay sharp.
FONT_LOAD_SIZE :: 64

// Frames to render before a --screenshot is taken, to give the window
// a moment to settle (size, focus) before it is captured.
SCREENSHOT_AFTER_FRAMES :: 3
