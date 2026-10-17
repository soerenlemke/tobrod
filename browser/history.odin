package browser

import "core:strings"

// Session history: the visited URLs and where we are in them.
// A new navigation drops everything after the current entry, back/forward
// only move the index, like in every browser.
History :: struct {
	entries: [dynamic]string, // owned
	index:   int,             // current entry, -1 while empty
}

history_init :: proc() -> History {
	return History{index = -1}
}

history_destroy :: proc(h: ^History) {
	for entry in h.entries {
		delete(entry)
	}
	delete(h.entries)
	h.index = -1
}

// A new page was opened (typed URL or link).
history_push :: proc(h: ^History, url: string) {
	// clone before freeing anything: url may point into an entry we drop
	new_entry := strings.clone(url)
	for i := len(h.entries) - 1; i > h.index; i -= 1 {
		delete(h.entries[i])
	}
	resize(&h.entries, h.index + 1)
	append(&h.entries, new_entry)
	h.index = len(h.entries) - 1
}

// The current page ended up somewhere else, e.g. after a redirect.
history_replace_current :: proc(h: ^History, url: string) {
	if h.index < 0 {
		history_push(h, url)
		return
	}
	new_entry := strings.clone(url)
	delete(h.entries[h.index])
	h.entries[h.index] = new_entry
}

history_current :: proc(h: ^History) -> (url: string, ok: bool) {
	if h.index < 0 {
		return "", false
	}
	return h.entries[h.index], true
}

history_can_back :: proc(h: ^History) -> bool {
	return h.index > 0
}

history_can_forward :: proc(h: ^History) -> bool {
	return h.index >= 0 && h.index < len(h.entries) - 1
}

history_back :: proc(h: ^History) -> (url: string, ok: bool) {
	if !history_can_back(h) {
		return "", false
	}
	h.index -= 1
	return h.entries[h.index], true
}

history_forward :: proc(h: ^History) -> (url: string, ok: bool) {
	if !history_can_forward(h) {
		return "", false
	}
	h.index += 1
	return h.entries[h.index], true
}
