package ui

import "core:strings"
import rl "vendor:raylib"

Error :: struct {
	message: string,
}

WindowSettings :: struct {
	name:        string,
	init_width:  i32,
	init_height: i32,
}

// One tab as the ui sees it: its page and what the tab bar and the buttons
// show. The browser keeps the rest (history, loader) and tells the ui which
// tabs exist (tab_add, tab_remove, tab_select); the ui only reports clicks
// and shortcuts (on_tab).
Tab_View :: struct {
	page_view:   PageView,
	title:       strings.Builder, // "" = still loading / no title: the tab bar shows the address
	address:     strings.Builder, // what the address bar shows for this tab
	loading:     bool,
	can_back:    bool,
	can_forward: bool,
}

MainWindow :: struct {
	address_bar:       AddressBar,
	nav_buttons:       NavButtons,
	tabs:              [dynamic]^Tab_View, // in tab bar order; the browser's tabs have the same order
	active:            int,
	window_name:       string,
	on_url_submit:     proc(url: string, ctx: rawptr),
	on_url_submit_ctx: rawptr,
	// href as written in the page; resolving it is up to the receiver.
	// new_tab: middle click or Ctrl+click
	on_link_click:     proc(href: string, new_tab: bool, ctx: rawptr),
	on_link_click_ctx: rawptr,
	on_navigate:       proc(action: Nav_Action, ctx: rawptr),
	on_navigate_ctx:   rawptr,
	on_tab:            proc(event: Tab_Event, ctx: rawptr),
	on_tab_ctx:        rawptr,
	// called at the start of every frame, e.g. to pick up loaded pages
	on_frame:          proc(ctx: rawptr),
	on_frame_ctx:      rawptr,
	should_close:      bool, // the last tab was closed
}

// The tab that is shown.
active_tab :: proc(ui: ^MainWindow) -> ^Tab_View {
	return ui.tabs[ui.active]
}

// While loading, reload turns into stop and the loading bar runs.
set_loading :: proc(ui: ^MainWindow, tab: ^Tab_View, loading: bool) {
	tab.loading = loading
	tab.page_view.loading = loading // image placeholders only while loading
}

// The browser tells the ui which navigation buttons are usable in a tab.
set_navigation_state :: proc(ui: ^MainWindow, tab: ^Tab_View, can_back, can_forward: bool) {
	tab.can_back = can_back
	tab.can_forward = can_forward
}

// What the address bar shows for a tab (the address bar itself follows the
// active tab).
tab_set_address :: proc(ui: ^MainWindow, tab: ^Tab_View, url: string) {
	strings.builder_reset(&tab.address)
	strings.write_string(&tab.address, url)
	if tab == active_tab(ui) {
		address_bar_set_text(&ui.address_bar, url)
	}
}

tab_set_title :: proc(ui: ^MainWindow, tab: ^Tab_View, title: string) {
	strings.builder_reset(&tab.title)
	strings.write_string(&tab.title, title)
	if tab == active_tab(ui) {
		update_window_title(ui)
	}
}

// A new tab at index (the end: len(ui.tabs)); it is not selected.
tab_add :: proc(ui: ^MainWindow, index: int) -> ^Tab_View {
	tab := new(Tab_View)
	tab.page_view = page_view_init(rl.GetScreenWidth(), rl.GetScreenHeight())
	strings.builder_init(&tab.title)
	strings.builder_init(&tab.address)
	inject_at(&ui.tabs, index, tab)
	if index <= ui.active && len(ui.tabs) > 1 {
		ui.active += 1 // the shown tab stays the same
	}
	return tab
}

// Closes a tab; the last one closes the window.
tab_remove :: proc(ui: ^MainWindow, index: int) {
	tab := ui.tabs[index]
	page_view_destroy(&tab.page_view)
	strings.builder_destroy(&tab.title)
	strings.builder_destroy(&tab.address)
	free(tab)
	ordered_remove(&ui.tabs, index)
	if len(ui.tabs) == 0 {
		ui.should_close = true
		ui.active = 0
		return
	}
	if index < ui.active || ui.active >= len(ui.tabs) {
		ui.active -= 1
	}
	show_active_tab(ui)
}

tab_select :: proc(ui: ^MainWindow, index: int) {
	ui.active = clamp(index, 0, len(ui.tabs) - 1)
	show_active_tab(ui)
}

// The address bar, the buttons and the window title follow the active tab.
@(private)
show_active_tab :: proc(ui: ^MainWindow) {
	if len(ui.tabs) == 0 {
		return
	}
	tab := active_tab(ui)
	address_bar_set_text(&ui.address_bar, strings.to_string(tab.address))
	ui.address_bar.focused = false
	update_window_title(ui)
}

// "Page title - tobrod", like other browsers.
@(private)
update_window_title :: proc(ui: ^MainWindow) {
	title := strings.to_string(active_tab(ui).title)
	text := ui.window_name if title == "" else strings.concatenate({title, " - ", ui.window_name}, context.temp_allocator)
	rl.SetWindowTitle(strings.clone_to_cstring(text, context.temp_allocator))
}

init :: proc(window_settings: WindowSettings) -> (MainWindow, Maybe(Error)) {
	name_cstring, alloc_err := strings.clone_to_cstring(window_settings.name)
	if alloc_err != .None {
		return {}, Error{message = "Could not allocate window name"}
	}
	defer delete(name_cstring)

	rl.SetConfigFlags({.WINDOW_RESIZABLE})
	rl.InitWindow(window_settings.init_width, window_settings.init_height, name_cstring)
	// raylib closes the window on Escape by default; we use Escape to stop loading
	rl.SetExitKey(.KEY_NULL)

	if err, has_err := fonts_init().?; has_err {
		rl.CloseWindow()
		return {}, err
	}

	address_bar := address_bar_init(window_settings.init_width)
	return MainWindow{address_bar = address_bar, window_name = strings.clone(window_settings.name)}, nil
}

destroy :: proc(ui: ^MainWindow) {
	for len(ui.tabs) > 0 {
		tab_remove(ui, len(ui.tabs) - 1)
	}
	delete(ui.tabs)
	delete(ui.window_name)
	strings.builder_destroy(&ui.address_bar.text)
	fonts_close()
	rl.CloseWindow()
}

// With a non-empty screenshot_path, the window is captured once the page has
// loaded (and a few frames have passed) and run returns instead of waiting
// for the user to close it.
// screenshot_scroll scrolls down that far before the capture (to check parts
// further down a page).
run :: proc(ui: ^MainWindow, screenshot_path := "", screenshot_scroll: f32 = 0) -> Maybe(Error) {
	scroll_pending := screenshot_scroll > 0
	frame := 0
	for !rl.WindowShouldClose() && !ui.should_close && len(ui.tabs) > 0 {
		frame += 1

		if ui.on_frame != nil {
			ui.on_frame(ui.on_frame_ctx)
		}

		if rl.IsWindowResized() {
			w := rl.GetScreenWidth()
			h := rl.GetScreenHeight()
			address_bar_handle_resize(&ui.address_bar, w, h)
			for tab in ui.tabs {
				page_view_handle_resize(&tab.page_view, w, h)
			}
		}

		// the tab bar first: it can close or switch the tab the rest works on
		tab_bar_handle_input(ui)
		if ui.should_close || len(ui.tabs) == 0 {
			break
		}
		tab := active_tab(ui)
		ui.nav_buttons.loading = tab.loading
		ui.nav_buttons.can_back = tab.can_back
		ui.nav_buttons.can_forward = tab.can_forward
		nav_buttons_handle_input(ui, &ui.nav_buttons)
		address_bar_handle_input(ui, &ui.address_bar)
		tab = active_tab(ui) // a callback may have opened another tab
		page_view_handle_mouse(ui, &tab.page_view)

		if wheel := rl.GetMouseWheelMove(); wheel != 0 {
			page_view_handle_scroll(&tab.page_view, wheel)
		}

		rl.BeginDrawing()
		rl.ClearBackground(rl.WHITE)

		page_view_render(&tab.page_view)
		tab_bar_render(ui)
		address_bar_render(&ui.address_bar)
		nav_buttons_render(&ui.nav_buttons)
		if tab.loading {
			loading_bar_render(ui.address_bar.rect.width)
		}

		// wait until the page has arrived, otherwise we'd capture an empty window
		if screenshot_path != "" && frame >= SCREENSHOT_AFTER_FRAMES && !tab.loading && scroll_pending && tab.page_view.page_layout != nil {
			// the layout exists now: scroll, and capture in one of the next frames
			page_view_scroll_to(&tab.page_view, screenshot_scroll)
			scroll_pending = false
			frame = 0
		}
		if screenshot_path != "" && frame >= SCREENSHOT_AFTER_FRAMES && !tab.loading && !scroll_pending {
			err := take_screenshot(screenshot_path)
			rl.EndDrawing()
			free_all(context.temp_allocator)
			return err
		}

		rl.EndDrawing()

		// cleaning up the temp allocated stuff each frame
		// (cstrings for drawing, scratch memory of the layout)
		free_all(context.temp_allocator)
	}
	return nil
}
