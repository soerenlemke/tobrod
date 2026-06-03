package ui

import "core:fmt"
import "core:strings"
import sdl "vendor:sdl3"

Error :: struct {
	message: string,
}

WindowSettings :: struct {
	name:        string,
	init_width:  i32,
	init_heihgt: i32,
}

MainWindow :: struct {
	window:      ^sdl.Window,
	renderer:    ^sdl.Renderer,
	address_bar: AddressBar,
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
		window_settings.init_heihgt,
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

	// load fonts to make them globally available
	fonts_init("assets/fonts/Inter_18pt-Regular.ttf")

	return MainWindow{window = window, renderer = renderer, address_bar = address_bar}, nil
}

destroy :: proc(ui: ^MainWindow) {
	sdl.DestroyWindow(ui.window)
	sdl.DestroyRenderer(ui.renderer)
	fonts_close()
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
				ui.address_bar.rect.w = f32(event.window.data1)
			}
		}

		sdl.SetRenderDrawColor(ui.renderer, 255, 255, 255, 255)
		sdl.RenderClear(ui.renderer)

		// TODO: page content

		address_bar_render(ui, &ui.address_bar)
		sdl.RenderPresent(ui.renderer)
	}
}
