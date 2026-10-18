package http

import "core:fmt"
import "core:hash"
import "core:os"
import "core:strconv"
import "core:strings"

// Recording and replaying responses, for the tools that compare tobrod with
// real pages (tools/compare.py, tools/cssreport): record a page once with
// everything it loads, then replay it as often as needed - fast, offline,
// and the page stays the same, so before/after pictures can be compared.
//
// One file per URL in the directory, named after a hash of the URL:
//   requested URL \n effective URL \n length of the header \n header body
// Recordings of real pages are their content: they stay out of git.

Recording_Mode :: enum {
	Off,
	Record, // load from the network and save every response
	Replay, // answer from the saved responses only, never the network
}

@(private)
recording: struct {
	mode: Recording_Mode,
	dir:  string,
}

// Call once at program start, before threads use a Client. dir must stay
// valid (a command line argument). Record creates the directory.
set_recording :: proc(mode: Recording_Mode, dir: string) -> Maybe(Http_Error) {
	recording.mode, recording.dir = mode, dir
	if mode == .Record && !os.exists(dir) {
		if err := os.make_directory_all(dir); err != nil {
			return Http_Error{code = .E_WRITE_ERROR, message = "cannot create the recording directory"}
		}
	}
	if mode == .Replay && !os.exists(dir) {
		return Http_Error{code = .E_READ_ERROR, message = "the recording directory does not exist"}
	}
	return nil
}

@(private)
recording_path :: proc(url: string) -> string {
	return fmt.tprintf("%s/%016x.http", recording.dir, hash.fnv64a(transmute([]byte)url))
}

@(private)
record_response :: proc(requested: string, response: Http_Response) {
	b := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&b, "%s\n%s\n%d\n", requested, response.url, len(response.header))
	strings.write_string(&b, response.header)
	strings.write_string(&b, response.body)
	// a failed write only means the page is missing when replaying
	_ = os.write_entire_file(recording_path(requested), b.buf[:])
}

// The saved response into the client's builders, like a real get. Not
// recorded: an error, as if the server were not reachable.
@(private)
replay_response :: proc(c: ^Client, url: string) -> (Http_Response, Maybe(Http_Error)) {
	not_recorded :: Http_Error{code = .E_COULDNT_CONNECT, message = "not in the recording"}
	data, err := os.read_entire_file(recording_path(url), context.temp_allocator)
	if err != nil {
		return {}, not_recorded
	}
	rest := string(data)
	requested, _ := strings.split_iterator(&rest, "\n")
	effective, _ := strings.split_iterator(&rest, "\n")
	length_line, _ := strings.split_iterator(&rest, "\n")
	header_length, ok := strconv.parse_int(length_line)
	if requested != url || !ok || header_length > len(rest) {
		return {}, not_recorded // a hash collision or a broken file
	}
	strings.write_string(&c.url_builder, effective)
	strings.write_string(&c.header_builder, rest[:header_length])
	strings.write_string(&c.body_builder, rest[header_length:])
	return {
			url = strings.to_string(c.url_builder),
			header = strings.to_string(c.header_builder),
			body = strings.to_string(c.body_builder),
		},
		nil
}
