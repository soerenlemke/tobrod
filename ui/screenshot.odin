package ui

import "core:fmt"
import "core:strings"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

// Must be called between BeginDrawing and EndDrawing, after everything is drawn:
// after EndDrawing the buffers are swapped and the back buffer is undefined.
// rl.TakeScreenshot is not used because it drops the directory part of the path.
take_screenshot :: proc(path: string) -> Maybe(Error) {
	// raylib batches draw calls; flush them so the framebuffer is complete
	rlgl.DrawRenderBatchActive()

	image := rl.LoadImageFromScreen()
	defer rl.UnloadImage(image)

	path_c := strings.clone_to_cstring(path, context.temp_allocator)
	if !rl.ExportImage(image, path_c) {
		return Error{message = fmt.tprintf("could not write screenshot to %s", path)}
	}
	return nil
}
