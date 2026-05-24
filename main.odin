package main

import "core:fmt"
import "core:strings"
import "http"


main :: proc() {
	strings_builder: strings.Builder
	strings.builder_init(&strings_builder)
	defer strings.builder_destroy(&strings_builder)

	body := http.get_body(&strings_builder, "https://example.com")
	fmt.println(body)
}
