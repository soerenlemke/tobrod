package ui

import "core:strings"
import sdl "vendor:sdl3"

// TODO: Basic; tab; management
// TODO: Navigation; buttons(back, forward, reload)<

Ui_Error :: struct {
	message: string,
}

Ui_WindowSettings :: struct {
	name:   string,
	width:  i32,
	heihgt: i32,
}

Ui_Window :: struct {
	window:   ^sdl.Window,
	renderer: ^sdl.Renderer,
}

ui_init :: proc(window_settings: Ui_WindowSettings) -> (Ui_Window, Maybe(Ui_Error)) {
	if !sdl.Init({.VIDEO}) {
		return {}, Ui_Error{message = string(sdl.GetError())}
	}

	name_cstring, alloc_err := strings.clone_to_cstring(window_settings.name)
	if alloc_err != .None {
		return {}, Ui_Error{message = "Could not allocate window name"}
	}
	defer delete(name_cstring)

	window := sdl.CreateWindow(
		name_cstring,
		window_settings.width,
		window_settings.heihgt,
		{.RESIZABLE},
	)
	if window == nil {
		sdl.Quit()
		return {}, Ui_Error{message = string(sdl.GetError())}
	}

	renderer := sdl.CreateRenderer(window, nil)
	if renderer == nil {
		sdl.DestroyWindow(window)
		sdl.Quit()
		return {}, Ui_Error{message = string(sdl.GetError())}
	}

	// load fonts to make them globally available
	ui_init_fonts("assets/fonts/Inter_18pt-Regular.ttf")

	return Ui_Window{window = window, renderer = renderer}, nil
}

ui_destroy :: proc(ui: ^Ui_Window) {
	sdl.DestroyWindow(ui.window)
	sdl.DestroyRenderer(ui.renderer)
	sdl.Quit()
}

ui_run :: proc(ui: ^Ui_Window) {
	w, h: i32
	sdl.GetWindowSize(ui.window, &w, &h)

	address_bar := ui_address_bar_init(w)
	ADDRESS_BAR_HEIGHT :: f32(36)

	running := true
	for running {
		event: sdl.Event
		for sdl.PollEvent(&event) {
			ui_address_bar_handle_event(ui, &address_bar, &event)

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

		ui_address_bar_render(ui, &address_bar)
		sdl.RenderPresent(ui.renderer)
	}
}
