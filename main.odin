package main

import "core:fmt"

import "http"
import "ui"

main :: proc() {
	window_settings := ui.Ui_WindowSettings {
		name   = "Browser",
		width  = 1024,
		heihgt = 768,
	}
	fmt.println("window settings:", window_settings)

	window, ui_err := ui.ui_init(window_settings)
	fmt.println("ui_init result:", window)
	if ui_err, ok := ui_err.?; ok {
		fmt.println("UI Error:", ui_err.message)
		return
	}
	defer ui.ui_destroy(&window)

	ui.ui_run(&window)

	// TODO: this has to be called when typing a url into address bar

	http_client := http.client_init()
	defer http.client_destroy(&http_client)

	http_response, http_err := http.client_get(&http_client, "https://example.com")
	if err, ok := http_err.?; ok {
		fmt.println("Error:", err.message)
	}

	fmt.println(http_response)
}
