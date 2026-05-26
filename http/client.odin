package http

import "base:runtime"
import "core:strings"
import "vendor:curl"

Http_Error :: struct {
	code:    curl.code,
	message: string,
}

Http_Response :: struct {
	header: string,
	body:   string,
}

Client :: struct {
	handle:         ^curl.CURL,
	header_builder: strings.Builder,
	body_builder:   strings.Builder,
}

client_init :: proc() -> Client {
	c: Client
	c.handle = curl.easy_init()
	strings.builder_init(&c.header_builder)
	strings.builder_init(&c.body_builder)

	return c
}

client_destroy :: proc(c: ^Client) {
	curl.easy_cleanup(c.handle)
	strings.builder_destroy(&c.header_builder)
	strings.builder_destroy(&c.body_builder)
}

client_get :: proc(c: ^Client, url: string) -> (Http_Response, Maybe(Http_Error)) {
	strings.builder_reset(&c.header_builder)
	strings.builder_reset(&c.body_builder)

	url_c := strings.clone_to_cstring(url)
	defer delete(url_c)

	curl.easy_setopt(c.handle, .URL, url_c)
	curl.easy_setopt(c.handle, .HEADERFUNCTION, write_callback)
	curl.easy_setopt(c.handle, .HEADERDATA, &c.header_builder) // header
	curl.easy_setopt(c.handle, .WRITEFUNCTION, write_callback)
	curl.easy_setopt(c.handle, .WRITEDATA, &c.body_builder) // body

	response_code := curl.easy_perform(c.handle)
	if response_code != .E_OK {
		return {}, Http_Error{code = response_code, message = string(curl.easy_strerror(response_code))}
	}

	return {
			header = strings.to_string(c.header_builder),
			body = strings.to_string(c.body_builder),
		},
		nil
}

write_callback :: proc "c" (ptr: rawptr, size, nmemb: uint, userdata: rawptr) -> uint {
	context = runtime.default_context()

	builder := cast(^strings.Builder)userdata
	chunk := string(([^]u8)(ptr)[:size * nmemb])
	strings.write_string(builder, chunk)

	return size * nmemb
}
