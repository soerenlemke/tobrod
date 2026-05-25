package http

import "base:runtime"
import "core:strings"
import "vendor:curl"

Http_Error :: struct {
	code:    curl.code,
	message: string,
}

Client :: struct {
	handle:          ^curl.CURL,
	strings_builder: strings.Builder,
}

client_init :: proc() -> Client {
	c: Client
	c.handle = curl.easy_init()
	strings.builder_init(&c.strings_builder)

	return c
}

client_destroy :: proc(c: ^Client) {
	curl.easy_cleanup(c.handle)
	strings.builder_destroy(&c.strings_builder)
}

client_get :: proc(c: ^Client, url: string) -> (string, Http_Error) {
	strings.builder_reset(&c.strings_builder)

	// passing a null terminated c string to libcurl
	url_c := strings.clone_to_cstring(url)
	defer delete(url_c)

	curl.easy_setopt(c.handle, .URL, url_c)
	curl.easy_setopt(c.handle, .WRITEFUNCTION, write_callback)
	curl.easy_setopt(c.handle, .WRITEDATA, &c.strings_builder)

	// TODO: introduce debug mode
	// curl.easy_setopt(c.handle, .VERBOSE, 1) -> verbose for debugging
	// curl.easy_setopt(c.handle, .VERBOSE, 0) -> verbose off for normal mode

	res := curl.easy_perform(c.handle)
	if res != .E_OK {
		return "", Http_Error{code = res, message = string(curl.easy_strerror(res))}
	}

	return strings.to_string(c.strings_builder), {}
}

write_callback :: proc "c" (ptr: rawptr, size, nmemb: uint, userdata: rawptr) -> uint {
	context = runtime.default_context()

	builder := cast(^strings.Builder)userdata
	chunk := string(([^]u8)(ptr)[:size * nmemb])
	strings.write_string(builder, chunk)

	return size * nmemb
}
