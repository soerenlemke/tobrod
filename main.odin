package main

import "core:fmt"

import "ui"

main :: proc() {
	window_settings := ui.Ui_WindowSettings {
		name   = "Browser",
		width  = 1024,
		heihgt = 768,
	}

	window, ui_err := ui.ui_init(window_settings)
	if ui_err, ok := ui_err.?; ok {
		fmt.println("UI Error:", ui_err.message)
		return
	}
	defer ui.ui_destroy(&window)

	ui.ui_run(&window)
}
