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

	return b, nil
}

run :: proc(b: ^Browser) {
	ui.run(&b.window)
}

destroy :: proc(b: ^Browser) {
	ui.renderer_destroy(&b.window.renderer)
	ui.destroy(&b.window)
	http.destroy(&b.http_client)
}

register_callbacks :: proc(b: ^Browser) {
	b.window.on_url_submit_ctx = b
	b.window.on_url_submit = proc(url: string, ctx: rawptr) {
		browser := cast(^Browser)ctx
		response, err := http.get(&browser.http_client, url)
		if http_err, ok := err.?; ok {
			browser.window.page_view.content = fmt.tprintf("Error: %v", http_err.message)
			return
		}

		browser.window.page_view.content = response.body
		fmt.println("reponse body", browser.window.page_view.content)
	}
}
