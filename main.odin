package main

import "core:fmt"
import "http"

main :: proc() {
	http_client := http.client_init()
	defer http.client_destroy(&http_client)

	response, err := http.client_get(&http_client, "https://example.com")
	if err.code != .E_OK {
		fmt.eprintln("Error: ", err.message)
	}

	fmt.println(response)
}
