package layout

import "core:slice"
import "../dom"
import "../svg"

// Paint order: which items are drawn over which (CSS "stacking").
//
// The normal flow is drawn first: its boxes, then its images and text. Then
// positioned elements (relative, absolute, fixed - those with a block box),
// each with all of its boxes, images and text, so they cover the flow below:
//
//   1. z-index < 0, lowest first
//   2. the normal flow
//   3. z-index auto or 0, in document order
//   4. z-index > 0, lowest first (the same z: in document order)
//
// An element with a z-index (not auto) is a stacking context: positioned
// elements inside it stay in its layer, whatever their z-index (we draw them
// in document order there). One with z-index: auto isn't: a positioned
// element inside it with a z-index of its own gets its own layer.
//
// While laying out, every positioned element is noted with its range of the
// display list (add_positioned); resolve_layers then sorts the items into
// layers, which the ui draws one after the other.
//
// opacity < 1 also makes an element a stacking context (with z-index 0). Its
// layer is drawn as a group: everything in it opaque into an image of its
// own, which is then faded (Layer.fade), so text on a background doesn't
// let the background shine through. Inside a stacking context there are no
// more layers, so there (and for inline elements) the colors of the items
// themselves are faded instead (item_fade): the same where nothing overlaps.

// The items of one layer, as ranges [first, end) of the lists of the layout.
Layer :: struct {
	boxes, images, runs: [2]int,
	fade:                f32, // opacity of the group, as in dom.Style.fade: 0 = opaque
	transform:           Maybe(svg.Matrix), // rotate/scale/skew, in page coordinates (transform.odin)
}

@(private)
Positioned :: struct {
	using range: Display_Range,
	z:           int,
	stacking:    bool, // has a z-index: a stacking context
	fade:        f32,  // the layer's opacity, if it gets one
	transform:   Maybe(svg.Matrix), // in the coordinates of its box at anchor (transform.odin)
	anchor:      [2]f32,
	pre, post:   int,  // when it started and ended: nesting of positioned elements
}

@(private)
add_positioned :: proc(b: ^Builder, range: Display_Range, z: Maybe(int), pre: int, fade: f32 = 0, transform: Maybe(svg.Matrix) = nil, anchor: [2]f32 = {}) {
	value, has_z := z.?
	append(&b.positioned, Positioned{range = range, z = value, stacking = has_z, fade = fade, transform = transform, anchor = anchor, pre = pre, post = b.seq})
	b.seq += 1
}

// What enter_layer changes while a positioned element is laid out.
@(private)
Layer_State :: struct {
	group_fade: f32,  // the opacity the current layer is drawn with
	in_context: bool, // inside a stacking context: no layers of their own
}

// Called before the content of a positioned element (or one with opacity) is
// laid out; returns the state to restore and the fade of its layer. Only an
// element outside of stacking contexts gets a layer of its own (resolve_layers).
@(private)
enter_layer :: proc(b: ^Builder, style: dom.Style, stacking: bool) -> (saved: Layer_State, fade: f32) {
	saved = {b.group_fade, b.in_context}
	if stacking && !b.in_context {
		fade = style.fade
		b.group_fade = style.fade
	}
	b.in_context ||= stacking
	return
}

@(private)
leave_layer :: proc(b: ^Builder, saved: Layer_State) {
	b.group_fade, b.in_context = saved.group_fade, saved.in_context
}

// Does the element have an opacity of its own (not only its ancestors')?
@(private)
has_own_opacity :: proc(node: ^dom.Node) -> bool {
	return node.parent != nil && node.style.fade > node.parent.style.fade
}

// How much an item's colors are faded: its opacity, without the part its
// layer is already drawn with.
@(private)
item_fade :: proc(b: ^Builder, style: dom.Style) -> f32 {
	if b.group_fade >= 1 {
		return 0 // the layer isn't drawn at all
	}
	return 1 - (1 - style.fade) / (1 - b.group_fade)
}

// Reorders boxes, images and runs of the layout into layers (see above) and
// returns the layers in paint order.
@(private)
resolve_layers :: proc(b: ^Builder) -> [dynamic]Layer {
	l := b.layout
	layers := make([dynamic]Layer, b.allocator)
	if len(b.positioned) == 0 {
		append(&layers, Layer{boxes = {0, len(l.boxes)}, images = {0, len(l.images)}, runs = {0, len(l.runs)}})
		return layers
	}

	// which positioned element an item belongs to (-1: the normal flow);
	// outer elements first, inner ones overwrite them - unless an outer one
	// is a stacking context, which keeps what is inside it
	entries := b.positioned[:]
	slice.sort_by(entries, proc(a, b: Positioned) -> bool {return a.pre < b.pre})
	owner := make([]int, len(entries), context.temp_allocator) // the entry that draws it
	box_of := make([]int, len(l.boxes), context.temp_allocator)
	image_of := make([]int, len(l.images), context.temp_allocator)
	run_of := make([]int, len(l.runs), context.temp_allocator)
	slice.fill(box_of, -1)
	slice.fill(image_of, -1)
	slice.fill(run_of, -1)
	for e, i in entries {
		owner[i] = i
		for j := i - 1; j >= 0; j -= 1 {
			outer := entries[j]
			if outer.pre < e.pre && e.post < outer.post && entries[owner[j]].stacking {
				owner[i] = owner[j] // inside a stacking context: stays in its layer
				break
			}
		}
		for k in e.first_box ..< e.end_box {
			box_of[k] = owner[i]
		}
		for k in e.first_image ..< e.end_image {
			image_of[k] = owner[i]
		}
		for k in e.first_run ..< e.end_run {
			run_of[k] = owner[i]
		}
	}

	// the layers in paint order: (group, z), stable, so the same key keeps
	// document order. Group 0: z < 0, 1: the normal flow (layer -1), 2: z >= 0.
	Key :: struct {
		layer, group, z: int,
		fade:            f32,
		transform:       Maybe(svg.Matrix),
	}
	keys := make([dynamic]Key, context.temp_allocator)
	append(&keys, Key{layer = -1, group = 1})
	for i in 0 ..< len(entries) {
		if owner[i] == i {
			append(&keys, Key{layer = i, group = 0 if entries[i].z < 0 else 2, z = entries[i].z, fade = entries[i].fade, transform = transform_of(entries[i])})
		}
	}
	slice.stable_sort_by(keys[:], proc(a, b: Key) -> bool {
		return a.group < b.group || (a.group == b.group && a.z < b.z)
	})

	boxes := make([dynamic]Box, 0, len(l.boxes), b.allocator)
	images := make([dynamic]Image_Item, 0, len(l.images), b.allocator)
	runs := make([dynamic]Text_Run, 0, len(l.runs), b.allocator)
	for key in keys {
		layer := Layer{boxes = {len(boxes), 0}, images = {len(images), 0}, runs = {len(runs), 0}, fade = key.fade, transform = key.transform}
		for box, k in l.boxes {
			if box_of[k] == key.layer {
				append(&boxes, box)
			}
		}
		for image, k in l.images {
			if image_of[k] == key.layer {
				append(&images, image)
			}
		}
		for run, k in l.runs {
			if run_of[k] == key.layer {
				append(&runs, run)
			}
		}
		layer.boxes[1], layer.images[1], layer.runs[1] = len(boxes), len(images), len(runs)
		append(&layers, layer)
	}
	l.boxes, l.images, l.runs = boxes, images, runs
	return layers
}

@(private)
transform_of :: proc(p: Positioned) -> Maybe(svg.Matrix) {
	if m, ok := p.transform.?; ok {
		return absolute_transform(m, p.anchor)
	}
	return nil
}
