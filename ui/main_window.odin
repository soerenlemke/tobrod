package ui

import "core:strings"
import rl "vendor:raylib"

Error :: struct {
	message: string,
}

WindowSettings :: struct {
	name:        string,
	init_width:  i32,
	init_height: i32,
}

MainWindow :: struct {
	address_bar:       AddressBar,
	nav_buttons:       NavButtons,
	page_view:         PageView,
	on_url_submit:     proc(url: string, ctx: rawptr),
	on_url_submit_ctx: rawptr,
	// href as written in the page; resolving it is up to the receiver
	on_link_click:     proc(href: string, ctx: rawptr),
	on_link_click_ctx: rawptr,
	on_navigate:       proc(action: Nav_Action, ctx: rawptr),
	on_navigate_ctx:   rawptr,
	// called at the start of every frame, e.g. to pick up loaded pages
	on_frame:          proc(ctx: rawptr),
	on_frame_ctx:      rawptr,
	loading:           bool,
}

// While loading, reload turns into stop and the loading bar runs.
set_loading :: proc(ui: ^MainWindow, loading: bool) {
	ui.loading = loading
	ui.nav_buttons.loading = loading
}

// The browser tells the ui which navigation buttons are usable.
set_navigation_state :: proc(ui: ^MainWindow, can_back, can_forward: bool) {
	ui.nav_buttons.can_back = can_back
	ui.nav_buttons.can_forward = can_forward
}

init :: proc(window_settings: WindowSettings) -> (MainWindow, Maybe(Error)) {
	name_cstring, alloc_err := strings.clone_to_cstring(window_settings.name)
	if alloc_err != .None {
		return {}, Error{message = "Could not allocate window name"}
	}
	defer delete(name_cstring)

	rl.SetConfigFlags({.WINDOW_RESIZABLE})
	rl.InitWindow(window_settings.init_width, window_settings.init_height, name_cstring)
	// raylib closes the window on Escape by default; we use Escape to stop loading
	rl.SetExitKey(.KEY_NULL)

	if err, has_err := fonts_init().?; has_err {
		rl.CloseWindow()
		return {}, err
	}

	address_bar := address_bar_init(window_settings.init_width)
	page_view := page_view_init(window_settings.init_width, window_settings.init_height)

	return MainWindow{address_bar = address_bar, page_view = page_view}, nil
}

destroy :: proc(ui: ^MainWindow) {
	page_view_destroy(&ui.page_view)
	strings.builder_destroy(&ui.address_bar.text)
	fonts_close()
	rl.CloseWindow()
}

// With a non-empty screenshot_path, the window is captured once the page has
// loaded (and a few frames have passed) and run returns instead of waiting
// for the user to close it.
// screenshot_scroll scrolls down that far before the capture (to check parts
// further down a page).
run :: proc(ui: ^MainWindow, screenshot_path := "", screenshot_scroll: f32 = 0) -> Maybe(Error) {
	scroll_pending := screenshot_scroll > 0
	frame := 0
	for !rl.WindowShouldClose() {
		frame += 1

		if ui.on_frame != nil {
			ui.on_frame(ui.on_frame_ctx)
		}

		if rl.IsWindowResized() {
			w := rl.GetScreenWidth()
			h := rl.GetScreenHeight()
			address_bar_handle_resize(&ui.address_bar, w, h)
			page_view_handle_resize(&ui.page_view, w, h)
		}

		nav_buttons_handle_input(ui, &ui.nav_buttons)
		address_bar_handle_input(ui, &ui.address_bar)
		page_view_handle_mouse(ui, &ui.page_view)

		if wheel := rl.GetMouseWheelMove(); wheel != 0 {
			page_view_handle_scroll(&ui.page_view, wheel)
		}

		rl.BeginDrawing()
		rl.ClearBackground(rl.WHITE)

		page_view_render(&ui.page_view)
		address_bar_render(&ui.address_bar)
		nav_buttons_render(&ui.nav_buttons)
		if ui.loading {
			loading_bar_render(ui.address_bar.rect.width)
		}

		// wait until the page has arrived, otherwise we'd capture an empty window
		if screenshot_path != "" && frame >= SCREENSHOT_AFTER_FRAMES && !ui.loading && scroll_pending && ui.page_view.page_layout != nil {
			// the layout exists now: scroll, and capture in one of the next frames
			page_view_scroll_to(&ui.page_view, screenshot_scroll)
			scroll_pending = false
			frame = 0
		}
		if screenshot_path != "" && frame >= SCREENSHOT_AFTER_FRAMES && !ui.loading && !scroll_pending {
			err := take_screenshot(screenshot_path)
			rl.EndDrawing()
			free_all(context.temp_allocator)
			return err
		}

		rl.EndDrawing()

		// cleaning up the temp allocated stuff each frame
		// (cstrings for drawing, scratch memory of the layout)
		free_all(context.temp_allocator)
	}
	return nil
}
