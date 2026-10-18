package svg

import "core:strconv"
import "core:strings"
import "../dom"

// Our own small SVG renderer: draws an <svg> element of our DOM (lexbor
// parses SVG, as part of HTML or as a file of its own) into an RGBA picture.
//
// Supported: the shapes path, rect (also rounded), circle, ellipse, line,
// polygon and polyline; filled and stroked with a color (also currentColor,
// the first color of a gradient), fill-rule, the stroke's width, caps, joins
// miter limit and dashes, fill-/stroke-opacity and opacity; transform; viewBox with
// the default "xMidYMid meet" (and "none"); groups and nested svg. Not yet:
// <use>, real gradients, text, clipping and masks.
//
// dom lowercases all names: viewbox, lineargradient, fill-rule.

Image :: struct {
	width, height: int,
	pixels:        [][4]u8, // RGBA, straight alpha, row by row
}

// The default size of an <svg> without width/height and without a viewBox
// (like any replaced element).
DEFAULT_SIZE :: [2]f32{300, 150}

// The <svg> element of a parsed SVG file (or the first one in a document).
find_root :: proc(node: ^dom.Node) -> ^dom.Node {
	if node.kind == .Element && node.tag == "svg" {
		return node
	}
	for child in node.children {
		if found := find_root(child); found != nil {
			return found
		}
	}
	return nil
}

// The size an <svg> wants: its width and height, or one from the other with
// the viewBox's aspect ratio. Without width and height it has no size of its
// own (has_size false), only the aspect ratio of its viewBox: then the
// viewBox's size is returned, the page decides how big it is.
natural_size :: proc(root: ^dom.Node) -> (size: [2]f32, has_size: bool) {
	w, has_w := length_attribute(root, "width")
	h, has_h := length_attribute(root, "height")
	box, has_box := view_box(root)
	switch {
	case has_w && has_h:
		return {w, h}, true
	case has_w && has_box && box[2] > 0:
		return {w, w * box[3] / box[2]}, true
	case has_h && has_box && box[3] > 0:
		return {h * box[2] / box[3], h}, true
	case has_box && box[2] > 0 && box[3] > 0:
		return {box[2], box[3]}, false
	case has_w:
		return {w, DEFAULT_SIZE.y}, true
	case has_h:
		return {DEFAULT_SIZE.x, h}, true
	}
	return DEFAULT_SIZE, true
}

// Draws root into a new picture of width x height pixels.
render :: proc(root: ^dom.Node, width, height: int, allocator := context.allocator) -> Image {
	image := Image{width, height, make([][4]u8, width * height, allocator)}
	m := viewport_transform(root, f32(width), f32(height))
	r := Renderer{image = &image, root = root}
	// the svg element's own fill and color are inherited by its children
	draw_children(&r, root, m, inherit_paint(&r, root, root_paint(root)))
	return image
}

// Parses an SVG file and draws it at its natural size times scale (one with
// only an aspect ratio at least MIN_RATIO_ONLY_WIDTH wide: the page will
// probably draw it big).
decode :: proc(data: []u8, scale: f32 = 1, allocator := context.allocator) -> (image: Image, natural: [2]f32, has_size: bool, ok: bool) {
	doc, err := dom.parse(string(data))
	if err != nil {
		return
	}
	defer dom.destroy(doc)
	root := find_root(doc.root)
	if root == nil {
		return
	}
	natural, has_size = natural_size(root)
	scale := scale
	if !has_size {
		scale = max(scale, MIN_RATIO_ONLY_WIDTH / natural.x)
	}
	width, height := int(natural.x * scale + 0.5), int(natural.y * scale + 0.5)
	if width <= 0 || height <= 0 || width > MAX_SIZE || height > MAX_SIZE {
		return
	}
	return render(root, width, height, allocator), natural, has_size, true
}

MIN_RATIO_ONLY_WIDTH :: f32(512)

// The largest picture we draw (per side), against absurd sizes.
MAX_SIZE :: 4096

// What is inherited down the tree.
@(private)
Paint :: struct {
	fill:           Maybe([4]u8), // nil = none
	fill_rule:      Fill_Rule,
	fill_opacity:   f32,
	stroke:         Maybe([4]u8), // nil = none (the default)
	stroke_width:   f32,          // in user units
	stroke_opacity: f32,
	line_cap:       Line_Cap,
	line_join:      Line_Join,
	miter_limit:    f32,
	dash_array:     []f32, // in user units; empty = solid
	dash_offset:    f32,
	color:          [4]u8, // for currentColor
}

@(private)
Renderer :: struct {
	image: ^Image,
	root:  ^dom.Node, // for finding gradients by id
}

@(private)
root_paint :: proc(root: ^dom.Node) -> Paint {
	// currentColor of an inline <svg> is the text color of the page
	color := root.style.color if root.style.color[3] > 0 else {0, 0, 0, 255}
	return {fill = [4]u8{0, 0, 0, 255}, fill_opacity = 1, stroke_width = 1, stroke_opacity = 1, miter_limit = 4, color = color}
}

// viewBox="x y w h" mapped into the picture: scaled evenly and centered
// (preserveAspectRatio xMidYMid meet), or stretched with "none".
@(private)
viewport_transform :: proc(root: ^dom.Node, width, height: f32) -> Matrix {
	box, ok := view_box(root)
	if !ok || box[2] <= 0 || box[3] <= 0 {
		// no viewBox: user units are pixels of the natural size
		natural, _ := natural_size(root)
		return {width / natural.x, 0, 0, height / natural.y, 0, 0}
	}
	sx, sy := width / box[2], height / box[3]
	if aspect, has := attribute(root, "preserveaspectratio"); has && strings.has_prefix(strings.trim_space(aspect), "none") {
		return {sx, 0, 0, sy, -box[0] * sx, -box[1] * sy}
	}
	s := min(sx, sy)
	dx := (width - box[2] * s) / 2 - box[0] * s
	dy := (height - box[3] * s) / 2 - box[1] * s
	return {s, 0, 0, s, dx, dy}
}

@(private)
view_box :: proc(node: ^dom.Node) -> (box: [4]f32, ok: bool) {
	value := attribute(node, "viewbox") or_return
	n := numbers_of(value)
	if len(n) != 4 {
		return
	}
	return {n[0], n[1], n[2], n[3]}, true
}

@(private)
draw_children :: proc(r: ^Renderer, node: ^dom.Node, m: Matrix, paint: Paint) {
	for child in node.children {
		if child.kind == .Element {
			draw_element(r, child, m, paint)
		}
	}
}

@(private)
draw_element :: proc(r: ^Renderer, node: ^dom.Node, parent_m: Matrix, parent_paint: Paint) {
	switch node.tag {
	case "defs", "symbol", "clippath", "mask", "lineargradient", "radialgradient", "pattern", "marker",
	     "title", "desc", "metadata", "style", "script", "text", "image", "foreignobject", "use":
		return // not drawn (or not supported yet)
	}
	if value, ok := property(node, "display"); ok && value == "none" {
		return
	}
	if value, ok := property(node, "visibility"); ok && (value == "hidden" || value == "collapse") {
		return
	}

	m := parent_m
	if value, ok := attribute(node, "transform"); ok {
		if t, valid := parse_transform(value); valid {
			m = multiply(parent_m, t)
		}
	}
	paint := inherit_paint(r, node, parent_paint)
	opacity: f32 = 1
	if value, ok := property(node, "opacity"); ok {
		opacity = clamp(parse_number(value) or_else 1, 0, 1)
	}

	switch node.tag {
	case "g", "a", "switch":
		// opacity of a group should apply to the group as a whole; we hand
		// it down to its shapes, which is the same as long as they don't overlap
		if opacity < 1 {
			paint.fill_opacity *= opacity
			paint.stroke_opacity *= opacity
		}
		draw_children(r, node, m, paint)
	case "svg":
		// a nested svg: its own viewport at x, y
		x := length_attribute(node, "x") or_else 0
		y := length_attribute(node, "y") or_else 0
		size, _ := natural_size(node)
		inner := multiply(m, Matrix{1, 0, 0, 1, x, y})
		inner = multiply(inner, viewport_transform(node, size.x, size.y))
		draw_children(r, node, inner, paint)
	case:
		fill_color, has_fill := paint.fill.?
		stroke_color, has_stroke := paint.stroke.?
		if !has_fill && !has_stroke {
			return
		}
		pb := path_builder(m)
		if !shape_outline(&pb, node) {
			return
		}
		// the fill first, the stroke over it; a line has no inside
		if has_fill && node.tag != "line" {
			fill(r.image.pixels, r.image.width, r.image.height, pb.polygons[:], paint.fill_rule, fill_color, paint.fill_opacity * opacity)
		}
		if has_stroke && paint.stroke_width > 0 {
			style := Stroke_Style{paint.stroke_width * pb.scale, paint.line_cap, paint.line_join, paint.miter_limit}
			polygons, closed := pb.polygons[:], pb.closed[:]
			if len(paint.dash_array) > 0 {
				pattern := make([]f32, len(paint.dash_array), context.temp_allocator)
				for length, i in paint.dash_array {
					pattern[i] = length * pb.scale
				}
				dashes, dashes_closed := dash_path(polygons, closed, pattern, paint.dash_offset * pb.scale)
				polygons, closed = dashes[:], dashes_closed[:]
			}
			outline := stroke_outline(polygons, closed, style)
			fill(r.image.pixels, r.image.width, r.image.height, outline[:], .Nonzero, stroke_color, paint.stroke_opacity * opacity)
		}
	}
}

// The outline of a shape element into the path builder; false if it isn't one.
@(private)
shape_outline :: proc(pb: ^Path_Builder, node: ^dom.Node) -> bool {
	switch node.tag {
	case "path":
		d := attribute(node, "d") or_return
		parse_path(pb, d)
	case "rect":
		x := length_attribute(node, "x") or_else 0
		y := length_attribute(node, "y") or_else 0
		w := length_attribute(node, "width") or_return
		h := length_attribute(node, "height") or_return
		if w <= 0 || h <= 0 {
			return false
		}
		rx, has_rx := length_attribute(node, "rx")
		ry, has_ry := length_attribute(node, "ry")
		if has_rx && !has_ry {
			ry = rx
		} else if has_ry && !has_rx {
			rx = ry
		}
		rx, ry = clamp(rx, 0, w / 2), clamp(ry, 0, h / 2)
		if rx > 0 && ry > 0 {
			move_to(pb, {x + rx, y})
			line_to(pb, {x + w - rx, y})
			arc_to(pb, {x + w - rx, y}, rx, ry, 0, false, true, {x + w, y + ry})
			line_to(pb, {x + w, y + h - ry})
			arc_to(pb, {x + w, y + h - ry}, rx, ry, 0, false, true, {x + w - rx, y + h})
			line_to(pb, {x + rx, y + h})
			arc_to(pb, {x + rx, y + h}, rx, ry, 0, false, true, {x, y + h - ry})
			line_to(pb, {x, y + ry})
			arc_to(pb, {x, y + ry}, rx, ry, 0, false, true, {x + rx, y})
		} else {
			move_to(pb, {x, y})
			line_to(pb, {x + w, y})
			line_to(pb, {x + w, y + h})
			line_to(pb, {x, y + h})
		}
		close_path(pb)
	case "circle", "ellipse":
		cx := length_attribute(node, "cx") or_else 0
		cy := length_attribute(node, "cy") or_else 0
		rx, ry: f32
		if node.tag == "circle" {
			rx = length_attribute(node, "r") or_return
			ry = rx
		} else {
			rx = length_attribute(node, "rx") or_return
			ry = length_attribute(node, "ry") or_return
		}
		if rx <= 0 || ry <= 0 {
			return false
		}
		// two half arcs
		move_to(pb, {cx + rx, cy})
		arc_to(pb, {cx + rx, cy}, rx, ry, 0, false, true, {cx - rx, cy})
		arc_to(pb, {cx - rx, cy}, rx, ry, 0, false, true, {cx + rx, cy})
		close_path(pb)
	case "line":
		x1 := length_attribute(node, "x1") or_else 0
		y1 := length_attribute(node, "y1") or_else 0
		x2 := length_attribute(node, "x2") or_else 0
		y2 := length_attribute(node, "y2") or_else 0
		move_to(pb, {x1, y1})
		line_to(pb, {x2, y2})
	case "polygon", "polyline":
		points := numbers_of(attribute(node, "points") or_return)
		if len(points) < 4 {
			return false
		}
		move_to(pb, {points[0], points[1]})
		for i := 2; i + 1 < len(points); i += 2 {
			line_to(pb, {points[i], points[i + 1]})
		}
		if node.tag == "polygon" {
			close_path(pb)
		}
	case:
		return false
	}
	return true
}

// fill, fill-rule, fill-opacity and color of an element, from its parent's.
@(private)
inherit_paint :: proc(r: ^Renderer, node: ^dom.Node, parent: Paint) -> Paint {
	paint := parent
	if value, ok := property(node, "color"); ok {
		paint.color = dom.parse_color(value, parent.color) or_else parent.color
	}
	if value, ok := property(node, "fill"); ok {
		paint.fill = parse_paint(r, value, paint.color, parent.fill)
	}
	if value, ok := property(node, "fill-rule"); ok {
		paint.fill_rule = .Evenodd if value == "evenodd" else .Nonzero
	}
	if value, ok := property(node, "fill-opacity"); ok {
		paint.fill_opacity = clamp(parse_number(value) or_else 1, 0, 1)
	}
	if value, ok := property(node, "stroke"); ok {
		paint.stroke = parse_paint(r, value, paint.color, parent.stroke)
	}
	if value, ok := property(node, "stroke-width"); ok {
		if width, valid := parse_number(strings.trim_suffix(value, "px")); valid && width >= 0 {
			paint.stroke_width = width
		}
	}
	if value, ok := property(node, "stroke-opacity"); ok {
		paint.stroke_opacity = clamp(parse_number(value) or_else 1, 0, 1)
	}
	if value, ok := property(node, "stroke-linecap"); ok {
		switch value {
		case "butt":
			paint.line_cap = .Butt
		case "round":
			paint.line_cap = .Round
		case "square":
			paint.line_cap = .Square
		}
	}
	if value, ok := property(node, "stroke-linejoin"); ok {
		switch value {
		case "miter", "miter-clip", "arcs":
			paint.line_join = .Miter
		case "round":
			paint.line_join = .Round
		case "bevel":
			paint.line_join = .Bevel
		}
	}
	if value, ok := property(node, "stroke-dasharray"); ok {
		paint.dash_array = parse_dash_array(value) or_else parent.dash_array
	}
	if value, ok := property(node, "stroke-dashoffset"); ok {
		if offset, valid := parse_number(strings.trim_suffix(value, "px")); valid {
			paint.dash_offset = offset
		}
	}
	if value, ok := property(node, "stroke-miterlimit"); ok {
		if limit, valid := parse_number(value); valid && limit >= 1 {
			paint.miter_limit = limit
		}
	}
	return paint
}

// stroke-dasharray: "none" (solid) or dash and gap lengths, separated by
// commas or spaces; an odd number of them is repeated to make it even. All
// zero is solid; a negative length makes the value invalid.
@(private)
parse_dash_array :: proc(value: string) -> (pattern: []f32, ok: bool) {
	if value == "none" {
		return nil, true
	}
	spaced, _ := strings.replace_all(value, ",", " ", context.temp_allocator)
	parts := strings.fields(spaced, context.temp_allocator)
	lengths := make([dynamic]f32, 0, 2 * len(parts), context.temp_allocator)
	total: f32 = 0
	for part in parts {
		length := strconv.parse_f32(strings.trim_suffix(part, "px")) or_return
		if length < 0 {
			return
		}
		append(&lengths, length)
		total += length
	}
	if len(lengths) == 0 {
		return
	}
	if total == 0 {
		return nil, true
	}
	if len(lengths) % 2 == 1 {
		append(&lengths, ..lengths[:])
	}
	return lengths[:], true
}

// A fill: none, a color, currentColor, or url(#gradient) - for which we take
// the color of its first stop (real gradients come later).
@(private)
parse_paint :: proc(r: ^Renderer, value: string, current: [4]u8, inherited: Maybe([4]u8)) -> Maybe([4]u8) {
	value := strings.trim_space(value)
	switch {
	case value == "none" || value == "transparent":
		return nil
	case value == "inherit":
		return inherited
	case value == "currentcolor" || value == "currentColor":
		return current
	case strings.has_prefix(value, "url("):
		close := strings.index_byte(value, ')')
		if close < 0 {
			return nil
		}
		id := strings.trim(value[len("url("):close], " '\"#")
		if gradient := find_by_id(r.root, id); gradient != nil {
			if color, ok := first_stop_color(gradient, current); ok {
				return color
			}
		}
		// a fallback color after the url
		if color, ok := dom.parse_color(strings.trim_space(value[close + 1:]), current); ok {
			return color
		}
		return nil
	}
	color, ok := dom.parse_color(strings.to_lower(value, context.temp_allocator), current)
	if !ok {
		return inherited // an invalid value is ignored
	}
	return color
}

@(private)
first_stop_color :: proc(gradient: ^dom.Node, current: [4]u8) -> (color: [4]u8, ok: bool) {
	for child in gradient.children {
		if child.kind == .Element && child.tag == "stop" {
			value := property(child, "stop-color") or_else "black"
			color = dom.parse_color(strings.to_lower(value, context.temp_allocator), current) or_return
			if opacity, has := property(child, "stop-opacity"); has {
				color[3] = u8(clamp(parse_number(opacity) or_else 1, 0, 1) * f32(color[3]))
			}
			return color, true
		}
	}
	// a gradient can take its stops from another one (xlink:href)
	return
}

@(private)
find_by_id :: proc(node: ^dom.Node, id: string) -> ^dom.Node {
	if node.kind == .Element {
		if value, ok := dom.attribute(node, "id"); ok && value == id {
			return node
		}
	}
	for child in node.children {
		if found := find_by_id(child, id); found != nil {
			return found
		}
	}
	return nil
}

// A presentation property: from style="" (wins) or the attribute.
@(private)
property :: proc(node: ^dom.Node, name: string) -> (value: string, ok: bool) {
	if style, has := dom.attribute(node, "style"); has {
		rest := style
		for declaration in strings.split_iterator(&rest, ";") {
			colon := strings.index_byte(declaration, ':')
			if colon < 0 {
				continue
			}
			if strings.equal_fold(strings.trim_space(declaration[:colon]), name) {
				return strings.trim_space(declaration[colon + 1:]), true
			}
		}
	}
	return attribute(node, name)
}

@(private)
attribute :: proc(node: ^dom.Node, name: string) -> (value: string, ok: bool) {
	value, ok = dom.attribute(node, name)
	return strings.trim_space(value), ok
}

// A length attribute in user units: "10", "10px"; percentages and other
// units are not supported (false).
@(private)
length_attribute :: proc(node: ^dom.Node, name: string) -> (value: f32, ok: bool) {
	s := attribute(node, name) or_return
	s = strings.trim_suffix(s, "px")
	return strconv.parse_f32(s)
}

@(private)
parse_number :: proc(s: string) -> (n: f32, ok: bool) {
	s := strings.trim_space(s)
	if strings.has_suffix(s, "%") {
		n = strconv.parse_f32(s[:len(s) - 1]) or_return
		return n / 100, true
	}
	return strconv.parse_f32(s)
}
