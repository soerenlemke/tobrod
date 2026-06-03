package ui

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
	window:   ^sdl.Window,
	renderer: ^sdl.Renderer,
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

	// load fonts to make them globally available
	fonts_init("assets/fonts/Inter_18pt-Regular.ttf")

	return MainWindow{window = window, renderer = renderer}, nil
}

destroy :: proc(ui: ^MainWindow) {
	sdl.DestroyWindow(ui.window)
	sdl.DestroyRenderer(ui.renderer)
	fonts_close()
	sdl.Quit()
}

run :: proc(ui: ^MainWindow) {
	w, h: i32
	sdl.GetWindowSize(ui.window, &w, &h)

	// TODO: address_bar should be part of main window -> init should be in ui init
	address_bar := address_bar_init(w)
	ADDRESS_BAR_HEIGHT :: f32(36)

	running := true
	for running {
		event: sdl.Event
		for sdl.PollEvent(&event) {
			address_bar_handle_event(ui, &address_bar, &event)

			#partial switch event.type {
			case .QUIT:
				running = false
			case .WINDOW_RESIZED:
				address_bar.rect.w = f32(event.window.data1)
			}
		}

		sdl.SetRenderDrawColor(ui.renderer, 255, 255, 255, 255)
		sdl.RenderClear(ui.renderer)

		// TODO: page content

		address_bar_render(ui, &address_bar)
		sdl.RenderPresent(ui.renderer)
	}
}
