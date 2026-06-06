package ui

import "core:fmt"
import "core:strings"
import sdl "vendor:sdl3"

// ui wide constants
ADDRESS_BAR_HEIGHT :: 36

Error :: struct {
	message: string,
}

WindowSettings :: struct {
	name:        string,
	init_width:  i32,
	init_height: i32,
}

MainWindow :: struct {
	window:            ^sdl.Window,
	renderer:          Renderer,
	address_bar:       AddressBar,
	page_view:         PageView,
	on_url_submit:     proc(url: string, ctx: rawptr),
	on_url_submit_ctx: rawptr,
}

init :: proc(window_settings: WindowSettings) -> (MainWindow, Maybe(Error)) {
	if !sdl.Init({.VIDEO}) {
		return {}, Error{message = string(sdl.GetError())}
	}

	name_cstring, alloc_err := strings.clone_to_cstring(window_settings.name)
	if alloc_err != .None {
		return {}, Error{message = "Could not allocate window name"}
	}
	defer delete(name_cstring)

	window := sdl.CreateWindow(
		name_cstring,
		window_settings.init_width,
		window_settings.init_height,
		{.RESIZABLE},
	)
	if window == nil {
		sdl.Quit()
		return {}, Error{message = string(sdl.GetError())}
	}

	renderer := sdl.CreateRenderer(window, nil)
	if renderer == nil {
		sdl.DestroyWindow(window)
		sdl.Quit()
		return {}, Error{message = string(sdl.GetError())}
	}

	address_bar, address_bar_error := address_bar_init(window_settings.init_width)
	if alloc_err, ok := address_bar_error.?; ok {
		sdl.DestroyRenderer(renderer)
		sdl.DestroyWindow(window)
		sdl.Quit()
		return {}, Error{message = fmt.tprintf("address bar init failed: %v", alloc_err)}
	}

	page_view := page_view_init(window_settings.init_width, window_settings.init_height)

	// load fonts to make them globally available
	fonts_init("assets/fonts/Inter_18pt-Regular.ttf")

	return MainWindow {
			window = window,
			renderer = Renderer{sdl_renderer = renderer},
			address_bar = address_bar,
			page_view = page_view,
		},
		nil
}

destroy :: proc(ui: ^MainWindow) {
	fonts_close()
	sdl.DestroyRenderer(ui.renderer.sdl_renderer)
	sdl.DestroyWindow(ui.window)
	sdl.Quit()
}

run :: proc(ui: ^MainWindow) {
	running := true
	for running {
		event: sdl.Event
		for sdl.PollEvent(&event) {
			address_bar_handle_event(ui, &ui.address_bar, &event)

			#partial switch event.type {
			case .QUIT:
				running = false
			case .WINDOW_RESIZED:
				address_bar_handle_resize(&ui.address_bar, event.window.data1, event.window.data2)
				page_view_handle_resize(&ui.page_view, event.window.data1, event.window.data2)
			}
		}

		sdl.SetRenderDrawColor(ui.renderer.sdl_renderer, 255, 255, 255, 255)
		sdl.RenderClear(ui.renderer.sdl_renderer)

		page_view_render(ui, &ui.page_view) // page view before address bar so bar is always overlaying
		address_bar_render(ui, &ui.address_bar)
		sdl.RenderPresent(ui.renderer.sdl_renderer)
	}
}
