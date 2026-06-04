package main

import "browser"
import "core:fmt"
import "ui"

main :: proc() {
	settings := ui.WindowSettings {
		name        = "Browser",
		init_width  = 1024,
		init_height = 768,
	}

	b, err := browser.init(settings)
	if err, ok := err.?; ok {
		fmt.println("Error:", err.message)
		return
	}
	defer browser.destroy(&b)

	browser.run(&b)
}
