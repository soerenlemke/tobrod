package browser

import "../http"
import "../ui"
import "core:fmt"

Browser :: struct {
	window:      ui.MainWindow,
	http_client: http.Client,
}

init :: proc(settings: ui.WindowSettings) -> (Browser, Maybe(ui.Error)) {
	b: Browser

	main_window, ui_err := ui.init(settings)
	if ui_err, ok := ui_err.?; ok {
		return {}, ui_err
	}
	b.window = main_window

	http_client, http_err := http.init()
	if http_err, ok := http_err.?; ok {
		ui.destroy(&b.window)
		return {}, ui.Error{message = fmt.tprintf("http client init failed: %v", http_err)}
	}
	b.http_client = http_client

	register_callbacks(&b)

	return b, nil
}

run :: proc(b: ^Browser) {
	ui.run(&b.window)
}

destroy :: proc(b: ^Browser) {
	ui.destroy(&b.window)
	http.destroy(&b.http_client)
}

register_callbacks :: proc(b: ^Browser) {
	// address_bar callbacks
	b.window.on_url_submit = proc(url: string) {
		fmt.println("Navigating to:", url)
	}

	// other callbacks ...
}
