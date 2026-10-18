package browser

import "../dom"
import "../http"
import "../layout"
import "../loader"
import "../ui"
import "core:fmt"
import "core:strings"

Browser :: struct {
	window: ui.MainWindow,
	tabs:   [dynamic]^Tab, // same order as window.tabs
}

// A tab: its page in the ui (view) and what it needs to load pages. Every
// tab has its own loader, i.e. its own worker thread and curl handle, so
// tabs load independently (also in the background).
Tab :: struct {
	view:        ^ui.Tab_View,
	page_loader: loader.Loader,  // field not named loader: that would hide the package
	loading_id:  loader.Request_Id, // the page we are waiting for, 0 if none
	// images of the current page that are still loading: request id -> src as
	// written in the page (owned)
	image_requests: map[loader.Request_Id]Image_Request,
	history:     History,           // the current entry is the base for relative links
}

init :: proc(settings: ui.WindowSettings) -> (b: ^Browser, err: Maybe(ui.Error)) {
	// before any thread uses curl
	if e, failed := http.global_init().?; failed {
		return nil, ui.Error{message = fmt.tprintf("curl init failed: %v", e.message)}
	}

	// on the heap: the ui callbacks and the loaders keep pointers to it,
	// so it must not move (a returned struct would be copied)
	b = new(Browser)

	main_window, ui_err := ui.init(settings)
	if e, failed := ui_err.?; failed {
		free(b)
		http.global_cleanup()
		return nil, e
	}
	b.window = main_window

	if _, e := new_tab(b, 0); e != nil {
		ui.destroy(&b.window)
		free(b)
		http.global_cleanup()
		return nil, e
	}
	return b, nil
}

destroy :: proc(b: ^Browser) {
	for len(b.tabs) > 0 {
		close_tab(b, len(b.tabs) - 1)
	}
	delete(b.tabs)
	ui.destroy(&b.window)
	free(b)
	http.global_cleanup()
}

// A new, empty tab at index; not selected.
@(private)
new_tab :: proc(b: ^Browser, index: int) -> (tab: ^Tab, err: Maybe(ui.Error)) {
	tab = new(Tab) // the loader's worker keeps a pointer to it
	tab.history = history_init()
	if e, failed := loader.init(&tab.page_loader).?; failed {
		history_destroy(&tab.history)
		free(tab)
		return nil, ui.Error{message = fmt.tprintf("http client init failed: %v", e.message)}
	}
	tab.view = ui.tab_add(&b.window, index)
	inject_at(&b.tabs, index, tab)
	return tab, nil
}

@(private)
close_tab :: proc(b: ^Browser, index: int) {
	tab := b.tabs[index]
	loader.destroy(&tab.page_loader) // stops the worker before anything it uses goes away
	forget_image_requests(tab)
	delete(tab.image_requests)
	history_destroy(&tab.history)
	ordered_remove(&b.tabs, index)
	ui.tab_remove(&b.window, index) // the last one closes the window
	free(tab)
}

@(private)
active_tab :: proc(b: ^Browser) -> ^Tab {
	return b.tabs[b.window.active]
}

// With a non-empty screenshot_path the window is captured to that file and run
// returns, after scrolling down screenshot_scroll pixels.
run :: proc(b: ^Browser, screenshot_path := "", screenshot_scroll: f32 = 0) -> Maybe(ui.Error) {
	return ui.run(&b.window, screenshot_path, screenshot_scroll)
}

register_callbacks :: proc(b: ^Browser) {
	b.window.on_url_submit_ctx = b
	b.window.on_url_submit = proc(input: string, ctx: rawptr) {
		browser := cast(^Browser)ctx
		navigate_typed(browser, input)
	}

	b.window.on_link_click_ctx = b
	b.window.on_link_click = proc(href: string, new_tab: bool, ctx: rawptr) {
		browser := cast(^Browser)ctx
		base, _ := history_current(&active_tab(browser).history)
		url, ok := http.resolve_url(base, href, context.temp_allocator)
		if !ok || !http.is_loadable_url(url) {
			return // e.g. mailto: or a broken href
		}
		if new_tab {
			open_in_new_tab(browser, url)
		} else {
			navigate(browser, url)
		}
	}

	b.window.on_navigate_ctx = b
	b.window.on_navigate = proc(action: ui.Nav_Action, ctx: rawptr) {
		browser := cast(^Browser)ctx
		tab := active_tab(browser)
		switch action {
		case .Back:
			if _, ok := history_back(&tab.history); ok {
				open_current(browser, tab)
			}
		case .Forward:
			if _, ok := history_forward(&tab.history); ok {
				open_current(browser, tab)
			}
		case .Reload:
			open_current(browser, tab)
		case .Stop:
			stop_loading(browser, tab)
		}
	}

	b.window.on_tab_ctx = b
	b.window.on_tab = proc(event: ui.Tab_Event, ctx: rawptr) {
		browser := cast(^Browser)ctx
		switch event.kind {
		case .New:
			// right after the current tab, like a browser; the address bar
			// waits for an address
			index := browser.window.active + 1
			if _, err := new_tab(browser, index); err == nil {
				ui.tab_select(&browser.window, index)
				browser.window.address_bar.focused = true
			}
		case .Select:
			ui.tab_select(&browser.window, event.index)
		case .Close:
			close_tab(browser, event.index)
		}
	}

	b.window.on_frame_ctx = b
	b.window.on_frame = proc(ctx: rawptr) {
		browser := cast(^Browser)ctx
		for tab in browser.tabs {
			receive_pages(browser, tab)
		}
	}
}

// Opens what was typed into the address bar (or given with --url):
// "example.com" is completed to "https://example.com".
navigate_typed :: proc(b: ^Browser, input: string) {
	url := http.complete_url(input, context.temp_allocator)
	if url == "" {
		return
	}
	navigate(b, url)
}

// Opens what was typed (or given with --tab) in a new tab at the end,
// loading in the background.
open_tab_typed :: proc(b: ^Browser, input: string) {
	url := http.complete_url(input, context.temp_allocator)
	if url == "" {
		return
	}
	if tab, err := new_tab(b, len(b.tabs)); err == nil {
		navigate_tab(b, tab, url)
	}
}

// Opens a new page in the active tab: a completed address or a clicked link.
navigate :: proc(b: ^Browser, url: string) {
	navigate_tab(b, active_tab(b), url)
}

@(private)
navigate_tab :: proc(b: ^Browser, tab: ^Tab, url: string) {
	// url may point into the address bar's text, which open_current overwrites
	url := strings.clone(url, context.temp_allocator)
	history_push(&tab.history, url)
	open_current(b, tab)
}

// A link opened with a middle click or Ctrl+click: a new tab right after
// the current one, loading in the background (the current tab stays).
@(private)
open_in_new_tab :: proc(b: ^Browser, url: string) {
	url := strings.clone(url, context.temp_allocator) // it points into the current page
	tab, err := new_tab(b, b.window.active + 1)
	if err != nil {
		return
	}
	navigate_tab(b, tab, url)
}

// Shows the tab's current history entry in its address and starts loading it.
@(private)
open_current :: proc(b: ^Browser, tab: ^Tab) {
	url, ok := history_current(&tab.history)
	if !ok {
		return
	}
	ui.tab_set_address(&b.window, tab.view, url)
	ui.set_navigation_state(&b.window, tab.view, history_can_back(&tab.history), history_can_forward(&tab.history))

	// only starts loading; the page arrives later in receive_pages.
	// The loader drops the queued images of the old page.
	forget_image_requests(tab)
	// @media is evaluated for the current size of the page view
	page_rect := tab.view.page_view.rect
	tab.loading_id = loader.load(&tab.page_loader, url, {page_rect.width, page_rect.height})
	ui.set_loading(&b.window, tab.view, true)
}

@(private)
stop_loading :: proc(b: ^Browser, tab: ^Tab) {
	loader.cancel(&tab.page_loader) // the page and its images
	tab.loading_id = 0
	forget_image_requests(tab)
	ui.set_loading(&b.window, tab.view, false)
}

// Called once per frame and tab: takes finished pages and images from the
// tab's loader. Results of older requests (another page meanwhile) are dropped.
@(private)
receive_pages :: proc(b: ^Browser, tab: ^Tab) {
	for {
		result, ok := loader.poll(&tab.page_loader)
		if !ok {
			return
		}
		switch result.kind {
		case .Page:
			if result.id == tab.loading_id {
				show_page(b, tab, &result)
			}
		case .Resource:
			if request, waiting := tab.image_requests[result.id]; waiting {
				if result.error == "" {
					ui.page_view_add_image(&tab.view.page_view, request.src, result.url, result.content_type, result.data, request.mask)
				}
				delete(request.src)
				delete_key(&tab.image_requests, result.id)
			}
		}
		loader.result_destroy(&result)
		update_loading_state(b, tab)
	}
}

@(private)
show_page :: proc(b: ^Browser, tab: ^Tab, result: ^loader.Result) {
	tab.loading_id = 0

	// after redirects we are somewhere else: remember and show that,
	// links on the page are relative to it
	if current, _ := history_current(&tab.history); result.url != "" && result.url != current {
		history_replace_current(&tab.history, result.url)
		ui.tab_set_address(&b.window, tab.view, result.url)
	}

	if result.error != "" {
		ui.tab_set_title(&b.window, tab.view, "Error")
		ui.page_view_set_content(&tab.view.page_view, fmt.tprintf("Error: %s", result.error))
		return
	}
	doc := result.document
	result.document = nil
	ui.tab_set_title(&b.window, tab.view, dom.document_title(doc))
	// the page view owns the document from now on
	ui.page_view_set_document(&tab.view.page_view, doc)
	request_images(b, tab, doc)
}

// An image the loader is fetching for the page: src as written in the page
// (the key for the layout), and whether it is a mask image (mask-image).
@(private)
Image_Request :: struct {
	src:  string,
	mask: bool,
}

// Queues the pictures of the page in the loader (<img src>, <video poster>,
// the background and mask images of visible elements), each src only once.
// data: URLs need no loading and go to the page view right away.
@(private)
request_images :: proc(b: ^Browser, tab: ^Tab, doc: ^dom.Document) {
	base, _ := history_current(&tab.history)
	requested := make(map[string]bool, allocator = context.temp_allocator)

	fetch :: proc(tab: ^Tab, src, base: string, mask: bool, requested: ^map[string]bool) {
		key := fmt.tprintf("%v %s", mask, src)
		if src == "" || key in requested {
			return
		}
		requested[key] = true
		if http.is_data_url(src) {
			if data, content_type, ok := http.decode_data_url(src, context.temp_allocator); ok {
				ui.page_view_add_image(&tab.view.page_view, src, "", content_type, data, mask)
			}
			return
		}
		url, resolved := http.resolve_url(base, src, context.temp_allocator)
		if resolved && http.is_loadable_url(url) {
			id := loader.load_resource(&tab.page_loader, url)
			tab.image_requests[id] = {strings.clone(src), mask}
		}
	}
	request :: proc(tab: ^Tab, node: ^dom.Node, base: string, requested: ^map[string]bool) {
		if node.kind != .Element || node.style.display == .None {
			return
		}
		// <img src> and the preview picture of <video poster>
		if layout.is_replaced_element(node.tag) {
			fetch(tab, layout.image_source(node), base, false, requested)
		}
		fetch(tab, node.style.background_image.image, base, false, requested)
		fetch(tab, node.style.mask.image, base, true, requested)
		for child in node.children {
			request(tab, child, base, requested)
		}
	}
	for child in doc.root.children {
		request(tab, child, base, &requested)
	}
}

// Like in a browser, a page counts as loaded once its images are there too:
// until then the loading bar runs and the stop button stays.
@(private)
update_loading_state :: proc(b: ^Browser, tab: ^Tab) {
	ui.set_loading(&b.window, tab.view, tab.loading_id != 0 || len(tab.image_requests) > 0)
}

@(private)
forget_image_requests :: proc(tab: ^Tab) {
	for _, request in tab.image_requests {
		delete(request.src)
	}
	clear(&tab.image_requests)
}
