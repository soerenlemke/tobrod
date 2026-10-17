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
	page_view:         PageView,
	on_url_submit:     proc(url: string, ctx: rawptr),
	on_url_submit_ctx: rawptr,
}

init :: proc(window_settings: WindowSettings) -> (MainWindow, Maybe(Error)) {
	name_cstring, alloc_err := strings.clone_to_cstring(window_settings.name)
	if alloc_err != .None {
		return {}, Error{message = "Could not allocate window name"}
	}
	defer delete(name_cstring)

	rl.SetConfigFlags({.WINDOW_RESIZABLE})
	rl.InitWindow(window_settings.init_width, window_settings.init_height, name_cstring)

	if err, has_err := fonts_init("assets/fonts/Inter_18pt-Regular.ttf").?; has_err {
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

run :: proc(ui: ^MainWindow) {
	for !rl.WindowShouldClose() {
		if rl.IsWindowResized() {
			w := rl.GetScreenWidth()
			h := rl.GetScreenHeight()
			address_bar_handle_resize(&ui.address_bar, w, h)
			page_view_handle_resize(&ui.page_view, w, h)
		}

		address_bar_handle_input(ui, &ui.address_bar)

		if wheel := rl.GetMouseWheelMove(); wheel != 0 {
			page_view_handle_scroll(&ui.page_view, wheel, ui.page_view.content_height)
		}

		rl.BeginDrawing()
		rl.ClearBackground(rl.WHITE)

		page_view_render(&ui.page_view)
		address_bar_render(&ui.address_bar)

		rl.EndDrawing()

		// cleaning up the temp allocated stuff each frame
		// e.g. wrap text is currently using the temp allocator
		free_all(context.temp_allocator)
	}
}
