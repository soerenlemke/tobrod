package ui

import "core:strings"
import sdl "vendor:sdl3"

// TODO: Address; bar
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

	return Ui_Window{window = window, renderer = renderer}, nil
}

ui_destroy :: proc(ui: ^Ui_Window) {
	sdl.DestroyWindow(ui.window)
	sdl.DestroyRenderer(ui.renderer)
	sdl.Quit()
}

ui_run :: proc(ui: ^Ui_Window) {
	running := true

	for running {
		event: sdl.Event
		for sdl.PollEvent(&event) {
			#partial switch event.type {
			case .QUIT:
				running = false
			case .KEY_DOWN:
				if event.key.key == sdl.K_ESCAPE {
					running = false
				}
			}
		}

		sdl.SetRenderDrawColor(ui.renderer, 255, 255, 255, 255)
		sdl.RenderClear(ui.renderer)

		sdl.RenderPresent(ui.renderer)
	}
}
