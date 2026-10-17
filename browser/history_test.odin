package browser

import "core:testing"

@(test)
test_history :: proc(t: ^testing.T) {
	h := history_init()
	defer history_destroy(&h)

	_, ok := history_current(&h)
	testing.expect(t, !ok, "empty history has no current entry")
	testing.expect(t, !history_can_back(&h) && !history_can_forward(&h))

	history_push(&h, "a")
	history_push(&h, "b")
	history_push(&h, "c")
	testing.expect(t, history_can_back(&h) && !history_can_forward(&h))

	url, _ := history_back(&h)
	testing.expect_value(t, url, "b")
	url, _ = history_back(&h)
	testing.expect_value(t, url, "a")
	_, ok = history_back(&h)
	testing.expect(t, !ok, "nothing before the first entry")

	url, _ = history_forward(&h)
	testing.expect_value(t, url, "b")
	testing.expect(t, history_can_forward(&h))

	// a new navigation in the middle drops the forward entries ("c")
	history_push(&h, "d")
	testing.expect(t, !history_can_forward(&h))
	testing.expect_value(t, len(h.entries), 3)
	url, _ = history_back(&h)
	testing.expect_value(t, url, "b")

	// a redirect replaces the current entry
	history_replace_current(&h, "b2")
	url, _ = history_current(&h)
	testing.expect_value(t, url, "b2")
	url, _ = history_forward(&h)
	testing.expect_value(t, url, "d")
}

@(test)
test_history_push_current_entry :: proc(t: ^testing.T) {
	h := history_init()
	defer history_destroy(&h)

	// pushing a string that points into the history itself must not use freed memory
	history_push(&h, "a")
	history_push(&h, "b")
	history_back(&h)
	history_push(&h, h.entries[1])
	url, _ := history_current(&h)
	testing.expect_value(t, url, "b")
}
