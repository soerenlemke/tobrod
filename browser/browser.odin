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

	register_callbacks(&b)

	return b, nil
}

run :: proc(b: ^Browser) {
	ui.run(&b.window)
}

destroy :: proc(b: ^Browser) {
	ui.destroy(&b.window)
}

register_callbacks :: proc(b: ^Browser) {
	// address_bar callbacks
	b.window.on_url_submit = proc(url: string) {
		fmt.println("Navigating to:", url)
	}

	// other callbacks ...
}
