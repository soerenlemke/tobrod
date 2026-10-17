package browser

import "../dom"
import "../http"
import "../loader"
import "../ui"
import "core:fmt"
import "core:strings"

Browser :: struct {
	window:      ui.MainWindow,
	page_loader: loader.Loader,  // field not named loader: that would hide the package
	loading_id:  loader.Request_Id, // the page we are waiting for, 0 if none
	// images of the current page that are still loading: request id -> src as
	// written in the page (owned)
	image_requests: map[loader.Request_Id]string,
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
	forget_image_requests(b)
	delete(b.image_requests)
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

	// only starts loading; the page arrives later in receive_pages.
	// The loader drops the queued images of the old page.
	forget_image_requests(b)
	// @media is evaluated for the current size of the page view
	page_rect := b.window.page_view.rect
	b.loading_id = loader.load(&b.page_loader, url, {page_rect.width, page_rect.height})
	ui.set_loading(&b.window, true)
}

@(private)
stop_loading :: proc(b: ^Browser) {
	loader.cancel(&b.page_loader) // the page and its images
	b.loading_id = 0
	forget_image_requests(b)
	ui.set_loading(&b.window, false)
}

// Called once per frame: takes finished pages and images from the loader.
// Results of older requests (another page meanwhile) are dropped.
@(private)
receive_pages :: proc(b: ^Browser) {
	for {
		result, ok := loader.poll(&b.page_loader)
		if !ok {
			return
		}
		switch result.kind {
		case .Page:
			if result.id == b.loading_id {
				show_page(b, &result)
			}
		case .Resource:
			if src, waiting := b.image_requests[result.id]; waiting {
				if result.error == "" {
					ui.page_view_add_image(&b.window.page_view, src, result.url, result.content_type, result.data)
				}
				delete(src)
				delete_key(&b.image_requests, result.id)
			}
		}
		loader.result_destroy(&result)
		update_loading_state(b)
	}
}

@(private)
show_page :: proc(b: ^Browser, result: ^loader.Result) {
	b.loading_id = 0

	// after redirects we are somewhere else: remember and show that,
	// links on the page are relative to it
	if current, _ := history_current(&b.history); result.url != "" && result.url != current {
		history_replace_current(&b.history, result.url)
		ui.address_bar_set_text(&b.window.address_bar, result.url)
	}

	if result.error != "" {
		ui.page_view_set_content(&b.window.page_view, fmt.tprintf("Error: %s", result.error))
		return
	}
	doc := result.document
	result.document = nil
	// the page view owns the document from now on
	ui.page_view_set_document(&b.window.page_view, doc)
	request_images(b, doc)
}

// Queues every <img> of the page in the loader, each src only once.
@(private)
request_images :: proc(b: ^Browser, doc: ^dom.Document) {
	base, _ := history_current(&b.history)
	requested := make(map[string]bool, allocator = context.temp_allocator)

	request :: proc(b: ^Browser, node: ^dom.Node, base: string, requested: ^map[string]bool) {
		if node.kind == .Element && node.tag == "img" {
			if src, ok := dom.attribute(node, "src"); ok && src != "" && !(src in requested) {
				requested[src] = true
				url, resolved := http.resolve_url(base, src, context.temp_allocator)
				if resolved && http.is_loadable_url(url) {
					id := loader.load_resource(&b.page_loader, url)
					b.image_requests[id] = strings.clone(src)
				}
			}
		}
		for child in node.children {
			request(b, child, base, requested)
		}
	}
	request(b, doc.root, base, &requested)
}

// Like in a browser, a page counts as loaded once its images are there too:
// until then the loading bar runs and the stop button stays.
@(private)
update_loading_state :: proc(b: ^Browser) {
	ui.set_loading(&b.window, b.loading_id != 0 || len(b.image_requests) > 0)
}

@(private)
forget_image_requests :: proc(b: ^Browser) {
	for _, src in b.image_requests {
		delete(src)
	}
	clear(&b.image_requests)
}
