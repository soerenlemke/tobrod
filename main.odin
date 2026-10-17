package main

import "browser"
import "core:flags"
import "core:fmt"
import "core:os"
import "ui"

// Command line options, mainly for scripted visual tests.
Options :: struct {
	url:        string `usage:"URL to load on startup."`,
	screenshot: string `usage:"Save a PNG of the window to this path, then exit."`,
}

main :: proc() {
	opts: Options
	flags.parse_or_exit(&opts, os.args, .Unix)

	if !run(opts) {
		os.exit(1)
	}
}

// Separate from main so the deferred cleanup runs before the process exits.
run :: proc(opts: Options) -> (ok: bool) {
	settings := ui.WindowSettings {
		name        = "Browser",
		init_width  = 1024,
		init_height = 768,
	}

	b, err := browser.init(settings)
	if err, has_err := err.?; has_err {
		fmt.eprintln("Error:", err.message)
		return false
	}
	defer browser.destroy(b)

	browser.register_callbacks(b)

	if opts.url != "" {
		browser.navigate(b, opts.url)
	}

	if err, has_err := browser.run(b, opts.screenshot).?; has_err {
		fmt.eprintln("Error:", err.message)
		return false
	}
	return true
}
