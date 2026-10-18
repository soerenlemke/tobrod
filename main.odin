package main

import "browser"
import "core:flags"
import "core:fmt"
import "core:os"
import "http"
import "ui"

// Command line options, mainly for scripted visual tests.
Options :: struct {
	url:        string `usage:"URL to load on startup."`,
	screenshot: string `usage:"Save a PNG of the window to this path, then exit."`,
	scroll:     f32    `usage:"With --screenshot: scroll down this many pixels first."`,
	record:     string `usage:"Save every HTTP response to this directory (see http/recording.odin)."`,
	replay:     string `usage:"Answer every request from a directory made with --record, without the network."`,
}

main :: proc() {
	opts: Options
	flags.parse_or_exit(&opts, os.args, .Unix)

	mode, dir := http.Recording_Mode.Off, ""
	switch {
	case opts.record != "" && opts.replay != "":
		fmt.eprintln("Error: --record and --replay don't go together")
		os.exit(1)
	case opts.record != "":
		mode, dir = .Record, opts.record
	case opts.replay != "":
		mode, dir = .Replay, opts.replay
	}
	if err, failed := http.set_recording(mode, dir).?; failed {
		fmt.eprintln("Error:", err.message)
		os.exit(1)
	}

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
		browser.navigate_typed(b, opts.url)
	}

	if err, has_err := browser.run(b, opts.screenshot, opts.scroll).?; has_err {
		fmt.eprintln("Error:", err.message)
		return false
	}
	return true
}
