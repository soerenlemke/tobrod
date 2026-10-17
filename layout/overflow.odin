package layout

import "../dom"

// overflow: hidden (and clip, scroll, auto: we can't scroll inside a box, so
// they clip, too). When an element that clips is done, everything it added to
// the display list - except its own box - gets the element's padding box as
// clip rectangle; content that was already clipped further inside keeps its
// rectangle, intersected with this one. Absolute elements whose containing
// block is outside of the element are placed later, so they are not clipped,
// like in CSS. The ui draws each item only inside its rectangle.

// Which axes an element clips. If only one axis is set to something that
// clips, visible on the other one becomes auto - which clips, too (except
// for overflow: clip).
@(private)
clips_overflow :: proc(style: dom.Style) -> (x, y: bool) {
	o := style.overflow
	x = o.x != .Visible || o.y == .Hidden
	y = o.y != .Visible || o.x == .Hidden
	return
}

// Clips what the element added (r) to its padding box. b.last_box is the
// element's border box from before a relative shift by offset.
@(private)
clip_contents :: proc(b: ^Builder, r: Display_Range, clip_x, clip_y: bool, offset: [2]f32) {
	box := b.last_box
	// an axis that doesn't clip gets a rectangle that is "endless" there
	FAR :: 1e9
	rect := Clip_Rect{-FAR, -FAR, 2 * FAR, 2 * FAR}
	if clip_x {
		rect.x = box.x + box.border[.Left] + offset.x
		rect.width = box.width - box.border[.Left] - box.border[.Right]
	}
	if clip_y {
		rect.y = box.y + box.border[.Top] + offset.y
		rect.height = box.height - box.border[.Top] - box.border[.Bottom]
	}
	l := b.layout
	append(&l.clips, rect)
	id := Clip(len(l.clips))

	apply :: proc(l: ^Layout, clip: ^Clip, id: Clip, rect: Clip_Rect) {
		if clip^ == 0 {
			clip^ = id
		} else {
			inner := &l.clips[clip^ - 1]
			inner^ = intersect(inner^, rect)
		}
	}
	for &run in l.runs[r.first_run:r.end_run] {
		apply(l, &run.clip, id, rect)
	}
	for &image in l.images[r.first_image:r.end_image] {
		apply(l, &image.clip, id, rect)
	}
	for &item, i in l.boxes[r.first_box:r.end_box] {
		if r.first_box + i != box.index { // the element's own box is not clipped
			apply(l, &item.clip, id, rect)
		}
	}
}

@(private)
intersect :: proc(a, b: Clip_Rect) -> Clip_Rect {
	x := max(a.x, b.x)
	y := max(a.y, b.y)
	right := min(a.x + a.width, b.x + b.width)
	bottom := min(a.y + a.height, b.y + b.height)
	return {x, y, max(right - x, 0), max(bottom - y, 0)}
}
