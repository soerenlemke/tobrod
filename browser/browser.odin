package browser

import "../dom"
import "../http"
import "../ui"
import "core:fmt"
import "core:strings"

Browser :: struct {
	window:      ui.MainWindow,
	http_client: http.Client,
	history:     History, // the current entry is the base for relative links
}

init :: proc(settings: ui.WindowSettings) -> (Browser, Maybe(ui.Error)) {
	b: Browser
	b.history = history_init()

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
	history_destroy(&b.history)
}

// With a non-empty screenshot_path the window is captured to that file and run returns.
run :: proc(b: ^Browser, screenshot_path := "") -> Maybe(ui.Error) {
	return ui.run(&b.window, screenshot_path)
}

register_callbacks :: proc(b: ^Browser) {
	b.window.on_url_submit_ctx = b
	b.window.on_url_submit = proc(url: string, ctx: rawptr) {
		browser := cast(^Browser)ctx
		navigate(browser, url)
	}

	b.window.on_link_click_ctx = b
	b.window.on_link_click = proc(href: string, ctx: rawptr) {
		browser := cast(^Browser)ctx
		base, _ := history_current(&browser.history)
		url, ok := http.resolve_url(base, href, context.temp_allocator)
		if !ok || !http.is_loadable_url(url) {
			return // e.g. mailto: or a broken href
		}
		navigate(browser, url)
	}

	b.window.on_navigate_ctx = b
	b.window.on_navigate = proc(action: ui.Nav_Action, ctx: rawptr) {
		browser := cast(^Browser)ctx
		switch action {
		case .Back:
			if _, ok := history_back(&browser.history); ok {
				open_current(browser)
			}
		case .Forward:
			if _, ok := history_forward(&browser.history); ok {
				open_current(browser)
			}
		case .Reload:
			open_current(browser)
		}
	}
}

// Opens a new page: typed into the address bar, a clicked link or --url.
navigate :: proc(b: ^Browser, url: string) {
	// url may point into the address bar's text, which open_current overwrites
	url := strings.clone(url, context.temp_allocator)
	history_push(&b.history, url)
	open_current(b)
}

// Shows and loads the current history entry.
@(private)
open_current :: proc(b: ^Browser) {
	url, ok := history_current(&b.history)
	if !ok {
		return
	}
	ui.address_bar_set_text(&b.window.address_bar, url)
	load_page(b, url)
	ui.set_navigation_state(&b.window, history_can_back(&b.history), history_can_forward(&b.history))
}

@(private)
load_page :: proc(b: ^Browser, url: string) {
	response, err := http.get(&b.http_client, url)
	if http_err, ok := err.?; ok {
		ui.page_view_set_content(&b.window.page_view, fmt.tprintf("Error: %v", http_err.message))
		return
	}

	// after redirects we are somewhere else: remember and show that,
	// links on the page are relative to it (url may be freed after this)
	if response.url != "" && response.url != url {
		history_replace_current(&b.history, response.url)
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
