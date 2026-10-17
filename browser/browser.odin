package browser

import "../dom"
import "../http"
import "../ui"
import "core:fmt"
import "core:strings"

Browser :: struct {
	window:      ui.MainWindow,
	http_client: http.Client,
	current_url: string, // owned; the base for relative links
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
	delete(b.current_url)
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

	b.window.on_link_click_ctx = b
	b.window.on_link_click = proc(href: string, ctx: rawptr) {
		browser := cast(^Browser)ctx
		url, ok := http.resolve_url(browser.current_url, href, context.temp_allocator)
		if !ok || !http.is_loadable_url(url) {
			return // e.g. mailto: or a broken href
		}
		navigate(browser, url)
	}
}

// Load a URL as if it had been typed into the address bar.
navigate :: proc(b: ^Browser, url: string) {
	ui.address_bar_set_text(&b.window.address_bar, url)
	load_page(b, url)
}

@(private)
load_page :: proc(b: ^Browser, url: string) {
	set_current_url(b, url)

	response, err := http.get(&b.http_client, url)
	if http_err, ok := err.?; ok {
		ui.page_view_set_content(&b.window.page_view, fmt.tprintf("Error: %v", http_err.message))
		return
	}

	// after redirects we are somewhere else: show that and resolve links against it
	if response.url != "" && response.url != b.current_url {
		set_current_url(b, response.url)
		ui.address_bar_set_text(&b.window.address_bar, response.url)
	}

	content_type, _ := http.header_value(response.header, "Content-Type")
	if strings.has_prefix(content_type, "text/html") {
		doc, parse_err := dom.parse(response.body)
		if e, ok := parse_err.?; ok {
			ui.page_view_set_content(&b.window.page_view, fmt.tprintf("Error: %v", e.message))
			return
		}
		// the page view owns the document from now on
		ui.page_view_set_document(&b.window.page_view, doc)
		return
	}

	ui.page_view_set_content(&b.window.page_view, response.body)
}

@(private)
set_current_url :: proc(b: ^Browser, url: string) {
	// clone first: url may point into the old current_url
	new_url := strings.clone(url)
	delete(b.current_url)
	b.current_url = new_url
}
