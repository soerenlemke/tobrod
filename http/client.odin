package http

import "base:runtime"
import "core:fmt"
import "core:strings"
import "vendor:curl"

get_body :: proc(strings_builder: ^strings.Builder, url: string) -> string {
	handle := curl.easy_init()
	defer curl.easy_cleanup(handle)

	curl.easy_setopt(handle, .URL, url)
	curl.easy_setopt(handle, .WRITEFUNCTION, write_callback)
	curl.easy_setopt(handle, .WRITEDATA, strings_builder)

	res := curl.easy_perform(handle)
	if res != .E_OK {
		fmt.eprintln("curl error:", curl.easy_strerror(res))
	}

	return strings.to_string(strings_builder^)
}

write_callback :: proc "c" (ptr: rawptr, size, nmemb: uint, userdata: rawptr) -> uint {
	context = runtime.default_context()

	builder := cast(^strings.Builder)userdata
	chunk := string(([^]u8)(ptr)[:size * nmemb])
	strings.write_string(builder, chunk)

	return size * nmemb
}
