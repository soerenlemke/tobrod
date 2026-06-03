package browser

import "../ui"
import "core:fmt"

Browser :: struct {
	window: ui.MainWindow,
}

init :: proc(settings: ui.WindowSettings) -> (Browser, Maybe(ui.Error)) {
	b: Browser

	main_window, ui_err := ui.init(settings)
	if ui_err, ok := ui_err.?; ok {
		return {}, ui_err
	}
	b.window = main_window

	// TODO: create on_url_submit in window
	b.window.on_url_submit = proc(url: string) {
		fmt.println("Navigiere zu:", url)
		// http_fetch(url)
	}

	return b, nil
}

run :: proc(b: ^Browser) {
	ui.run(&b.window)
}

destroy :: proc(b: ^Browser) {
	ui.destroy(&b.window)
}
