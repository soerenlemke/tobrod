package browser

import "../http"
import "../loader"
import "../ui"
import "core:fmt"
import "core:strings"

Browser :: struct {
	window:      ui.MainWindow,
	page_loader: loader.Loader,  // field not named loader: that would hide the package
	loading_id:  loader.Request_Id, // the request we are waiting for, 0 if none
	history:     History,           // the current entry is the base for relative links
}

init :: proc(settings: ui.WindowSettings) -> (b: ^Browser, err: Maybe(ui.Error)) {
	// before any thread uses curl
	if e, failed := http.global_init().?; failed {
		return nil, ui.Error{message = fmt.tprintf("curl init failed: %v", e.message)}
	}

	// on the heap: the ui callbacks and the loader keep pointers to it,
	// so it must not move (a returned struct would be copied)
	b = new(Browser)
	b.history = history_init()

	main_window, ui_err := ui.init(settings)
	if e, failed := ui_err.?; failed {
		free(b)
		http.global_cleanup()
		return nil, e
	}
	b.window = main_window

	if e, failed := loader.init(&b.page_loader).?; failed {
		ui.destroy(&b.window)
		free(b)
		http.global_cleanup()
		return nil, ui.Error{message = fmt.tprintf("http client init failed: %v", e.message)}
	}

	return b, nil
}

destroy :: proc(b: ^Browser) {
	loader.destroy(&b.page_loader) // stops the worker before anything it uses goes away
	ui.destroy(&b.window)
	history_destroy(&b.history)
	free(b)
	http.global_cleanup()
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
		case .Stop:
			stop_loading(browser)
		}
	}

	b.window.on_frame_ctx = b
	b.window.on_frame = proc(ctx: rawptr) {
		browser := cast(^Browser)ctx
		receive_pages(browser)
	}
}

// Opens a new page: typed into the address bar, a clicked link or --url.
navigate :: proc(b: ^Browser, url: string) {
	// url may point into the address bar's text, which open_current overwrites
	url := strings.clone(url, context.temp_allocator)
	history_push(&b.history, url)
	open_current(b)
}

// Shows the current history entry in the address bar and starts loading it.
@(private)
open_current :: proc(b: ^Browser) {
	url, ok := history_current(&b.history)
	if !ok {
		return
	}
	ui.address_bar_set_text(&b.window.address_bar, url)
	ui.set_navigation_state(&b.window, history_can_back(&b.history), history_can_forward(&b.history))

	// only starts loading; the page arrives later in receive_pages
	b.loading_id = loader.load(&b.page_loader, url)
	ui.set_loading(&b.window, true)
}

@(private)
stop_loading :: proc(b: ^Browser) {
	loader.cancel(&b.page_loader)
	b.loading_id = 0
	ui.set_loading(&b.window, false)
}

// Called once per frame: takes finished pages from the loader and shows the
// one we are waiting for. Results of older requests are dropped.
@(private)
receive_pages :: proc(b: ^Browser) {
	for {
		result, ok := loader.poll(&b.page_loader)
		if !ok {
			return
		}
		if result.id != b.loading_id {
			loader.result_destroy(&result)
			continue
		}
		b.loading_id = 0
		ui.set_loading(&b.window, false)

		// after redirects we are somewhere else: remember and show that,
		// links on the page are relative to it
		if current, _ := history_current(&b.history); result.url != "" && result.url != current {
			history_replace_current(&b.history, result.url)
			ui.address_bar_set_text(&b.window.address_bar, result.url)
		}

		if result.error != "" {
			ui.page_view_set_content(&b.window.page_view, fmt.tprintf("Error: %s", result.error))
		} else {
			// the page view owns the document from now on
			ui.page_view_set_document(&b.window.page_view, result.document)
			result.document = nil
		}
		loader.result_destroy(&result)
	}
}
