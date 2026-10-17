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

destroy :: proc(b: ^Browser) {
	ui.destroy(&b.window)
	http.destroy(&b.http_client)
}

// With a non-empty screenshot_path the window is captured to that file and run returns.
run :: proc(b: ^Browser, screenshot_path := "") -> Maybe(ui.Error) {
	return ui.run(&b.window, screenshot_path)
}

register_callbacks :: proc(b: ^Browser) {
	b.window.on_url_submit_ctx = b
	b.window.on_url_submit = proc(url: string, ctx: rawptr) {
		browser := cast(^Browser)ctx
		load_page(browser, url)
	}
}

// Load a URL as if it had been typed into the address bar.
navigate :: proc(b: ^Browser, url: string) {
	ui.address_bar_set_text(&b.window.address_bar, url)
	load_page(b, url)
}

@(private)
load_page :: proc(b: ^Browser, url: string) {
	response, err := http.get(&b.http_client, url)
	if http_err, ok := err.?; ok {
		ui.page_view_set_content(&b.window.page_view, fmt.tprintf("Error: %v", http_err.message))
		return
	}

	ui.page_view_set_content(&b.window.page_view, response.body)
}
