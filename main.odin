package main

import "core:fmt"
import "core:strings"
import "http"


main :: proc() {
	http_client := http.client_init()
	defer http.client_destroy(&http_client)

	response := http.client_get(&http_client, "https://example.com")
	fmt.println(response)
}
