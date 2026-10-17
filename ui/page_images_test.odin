package ui

import "core:testing"

@(test)
test_image_file_type :: proc(t: ^testing.T) {
	cases := []struct {
		content_type, url: string,
		file_type:         cstring,
		ok:                bool,
	} {
		{"image/png", "http://x/a", ".png", true},
		{"image/jpeg; charset=binary", "http://x/a.png", ".jpg", true}, // content type wins
		{"application/octet-stream", "http://x/photo.JPEG?size=2#top", ".jpg", true},
		{"", "http://x/anim.gif", ".gif", true},
		{"image/svg+xml", "http://x/logo.svg", nil, false}, // SVG would need a vector renderer
		{"text/html", "http://x/missing", nil, false},
	}
	for c in cases {
		file_type, ok := image_file_type(c.content_type, c.url)
		testing.expectf(t, ok == c.ok && file_type == c.file_type, "%q %q: got %v %v", c.content_type, c.url, file_type, ok)
	}
}
