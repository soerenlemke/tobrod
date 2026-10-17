package dom

import "core:strings"

// RGBA, 0..255 per channel. Our own type so dom doesn't depend on raylib.
Color :: [4]u8

// Computed style of an element. Only what we use so far.
Style :: struct {
	display:     Display,
	color:       Color,
	font_size:   f32, // px
	font_weight: int, // 1..1000, 400 = normal, 700 = bold
	text_align:  Text_Align,
	visibility:  Visibility, // inherited, but a child can be visible again
	list_style:  List_Style, // inherited from ul/ol to the li
	position:    Position,   // not inherited
	float:       Float,      // not inherited
	clear:       Clear,      // not inherited
	vertical_align:  Vertical_Align, // table cells only
	border_collapse: bool,           // tables: no spacing between the cells (inherited)
	caption_bottom:  bool,           // caption-side: bottom (inherited)

	// box model, not inherited (see box_style.odin)
	margin:      Edges,
	padding:     Edges,
	width:       Length, // .Auto = fill the available width
	height:      Length, // only used for images so far
	max_width:   Length, // .Auto = none
	background:  Color,  // alpha 0 = transparent
	border:      Borders,
	flex:        Flex,   // flexbox, see flex_style.odin
}

// justify is drawn like left for now
Text_Align :: enum {
	Left,
	Center,
	Right,
}

Visibility :: enum {
	Visible,
	Hidden, // takes up its space, but is not drawn ("collapse" too)
}

// The marker of list items. Alphabetic and roman styles are drawn as numbers.
List_Style :: enum {
	Disc,
	Circle,
	Square,
	Decimal,
	None,
}

Float :: enum {
	None,
	Left,
	Right,
}

Clear :: enum {
	None,
	Left,
	Right,
	Both,
}

// Absolute and fixed elements are taken out of the flow; we don't place them
// yet, so they are not drawn at all. Relative and sticky act like static.
Position :: enum {
	Static,
	Relative,
	Absolute,
	Fixed,
	Sticky,
}

Display :: enum {
	Inline, // default for unknown elements, like in CSS
	Block,
	List_Item,
	None,
	// tables (see layout/table.odin)
	Table,
	Table_Row_Group, // thead, tbody, tfoot
	Table_Row,
	Table_Cell,
	Table_Caption,
	Flex, // flexbox container (layout/flex.odin); inline-flex is treated like flex
}

// Vertical position of the content in a table cell. baseline is drawn like top.
Vertical_Align :: enum {
	Top,
	Middle,
	Bottom,
}

// Style of the document node: the start values everything inherits from.
ROOT_STYLE :: Style {
	display     = .Block,
	color       = {0, 0, 0, 255},
	font_size   = ROOT_FONT_SIZE,
	font_weight = 400,
	width       = AUTO,
	height      = AUTO,
	max_width   = AUTO,
	border      = INITIAL_BORDERS,
	flex        = INITIAL_FLEX,
}

// Initial value of display in CSS, used for "initial" and "unset".
@(private)
INITIAL_DISPLAY :: Display.Inline

LINK_COLOR :: Color{0, 0, 238, 255} // #0000ee, the classic link blue

// Style of an element before author CSS:
// 1. inherited properties (color, font-size, font-weight) come from the parent,
// 2. then the built-in defaults for the tag, like the "user agent stylesheet"
//    of a real browser (simplified from the HTML spec).
default_style :: proc(tag: string, has_hidden_attribute: bool, parent: Style) -> Style {
	style := Style {
		display     = default_display(tag),
		color       = parent.color,
		font_size   = parent.font_size,
		font_weight = parent.font_weight,
		text_align  = parent.text_align,
		visibility  = parent.visibility,
		list_style  = parent.list_style,
		border_collapse = parent.border_collapse,
		caption_bottom  = parent.caption_bottom,
		width       = AUTO,
		height      = AUTO,
		max_width   = AUTO,
		border      = INITIAL_BORDERS,
		flex        = INITIAL_FLEX,
	}
	default_box(tag, &style)
	if has_hidden_attribute {
		style.display = .None
	}

	switch tag {
	case "h1":
		style.font_size = parent.font_size * 2
		style.font_weight = 700
	case "h2":
		style.font_size = parent.font_size * 1.5
		style.font_weight = 700
	case "h3":
		style.font_size = parent.font_size * 1.17
		style.font_weight = 700
	case "h4":
		style.font_weight = 700
	case "h5":
		style.font_size = parent.font_size * 0.83
		style.font_weight = 700
	case "h6":
		style.font_size = parent.font_size * 0.67
		style.font_weight = 700
	case "b", "strong", "dt":
		style.font_weight = 700
	case "th":
		style.font_weight = 700
		style.text_align = .Center
		style.vertical_align = .Middle
	case "small":
		style.font_size = parent.font_size / 1.2
	case "a":
		style.color = LINK_COLOR
	case "center":
		style.text_align = .Center
	case "ol":
		style.list_style = .Decimal
	case "td":
		style.vertical_align = .Middle
	case "ul":
		style.list_style = .Disc
	}
	return style
}

// 3. Applies one value from the CSS cascade. Unknown or unsupported values are
// ignored, so the default stays (like a browser drops invalid declarations).
apply_declaration :: proc(style: ^Style, property, value: string, parent: Style) {
	switch property {
	case "display":
		switch value {
		case "inherit":
			style.display = parent.display
		case "initial", "unset":
			style.display = INITIAL_DISPLAY // display is not inherited
		case:
			if display, ok := parse_display(value); ok {
				style.display = display
			}
		}
	case "color":
		switch value {
		case "inherit", "unset":
			style.color = parent.color
		case "initial":
			style.color = ROOT_STYLE.color
		case:
			if color, ok := parse_color(value, parent.color); ok {
				style.color = color
			}
		}
	case "font-size":
		switch value {
		case "inherit", "unset":
			style.font_size = parent.font_size
		case "initial":
			style.font_size = ROOT_STYLE.font_size
		case:
			if size, ok := parse_font_size(value, parent.font_size); ok {
				style.font_size = size
			}
		}
	case "font-weight":
		switch value {
		case "inherit", "unset":
			style.font_weight = parent.font_weight
		case "initial":
			style.font_weight = ROOT_STYLE.font_weight
		case:
			if weight, ok := parse_font_weight(value, parent.font_weight); ok {
				style.font_weight = weight
			}
		}
	case "text-align":
		switch value {
		case "inherit", "unset":
			style.text_align = parent.text_align
		case "initial", "left", "start", "justify":
			style.text_align = .Left
		case "center":
			style.text_align = .Center
		case "right", "end":
			style.text_align = .Right
		}
	case "visibility":
		switch value {
		case "inherit", "unset":
			style.visibility = parent.visibility
		case "visible", "initial":
			style.visibility = .Visible
		case "hidden", "collapse":
			style.visibility = .Hidden
		}
	case "position":
		switch value {
		case "static", "initial", "unset":
			style.position = .Static
		case "relative":
			style.position = .Relative
		case "absolute":
			style.position = .Absolute
		case "fixed":
			style.position = .Fixed
		case "sticky":
			style.position = .Sticky
		case "inherit":
			style.position = parent.position
		}
	case "float":
		switch value {
		case "left", "inline-start":
			style.float = .Left
		case "right", "inline-end":
			style.float = .Right
		case "none", "initial", "unset":
			style.float = .None
		}
	case "clear":
		switch value {
		case "left", "inline-start":
			style.clear = .Left
		case "right", "inline-end":
			style.clear = .Right
		case "both":
			style.clear = .Both
		case "none", "initial", "unset":
			style.clear = .None
		}
	case "vertical-align":
		switch value {
		case "top", "text-top", "baseline", "initial", "unset":
			style.vertical_align = .Top
		case "middle":
			style.vertical_align = .Middle
		case "bottom", "text-bottom":
			style.vertical_align = .Bottom
		case "inherit":
			style.vertical_align = parent.vertical_align
		}
	case "caption-side":
		switch value {
		case "bottom":
			style.caption_bottom = true
		case "top", "initial":
			style.caption_bottom = false
		case "inherit", "unset":
			style.caption_bottom = parent.caption_bottom
		}
	case "border-collapse":
		switch value {
		case "collapse":
			style.border_collapse = true
		case "separate", "initial":
			style.border_collapse = false
		case "inherit", "unset":
			style.border_collapse = parent.border_collapse
		}
	case "list-style", "list-style-type":
		if value == "inherit" || value == "unset" {
			style.list_style = parent.list_style
		} else if list_style, ok := parse_list_style(value); ok {
			style.list_style = list_style
		}
	case "flex", "flex-direction", "flex-wrap", "flex-flow", "justify-content", "align-items", "align-self",
	     "gap", "row-gap", "column-gap", "flex-grow", "flex-shrink", "flex-basis":
		apply_flex_declaration(style, property, value)
	case:
		apply_box_declaration(style, property, value)
	}
}

// Properties we take from the cascade, in the order they are applied.
// Shorthands come before their longhands, so a longhand wins over a shorthand
// of the same element. (We only get the winning value per property from lexbor,
// not its specificity, so `.a.b { margin: 0 }` vs `.a { margin-top: 5px }` comes
// out wrong. Good enough for now.)
// font-size comes before the box properties, because em in margins refers to it.
STYLE_PROPERTIES :: [?]string {
	"display", "color", "font-size", "font-weight", "text-align",
	"visibility", "position", "float", "clear", "list-style", "list-style-type", "vertical-align", "border-collapse", "caption-side",
	"margin", "margin-top", "margin-right", "margin-bottom", "margin-left",
	"padding", "padding-top", "padding-right", "padding-bottom", "padding-left",
	"width", "height", "max-width",
	"background", "background-color",
	"flex-direction", "flex-wrap", "flex-flow", "justify-content", "align-items", "align-self",
	"gap", "row-gap", "column-gap", "flex", "flex-grow", "flex-shrink", "flex-basis",
	"border", "border-width", "border-style", "border-color",
	"border-top", "border-right", "border-bottom", "border-left",
	"border-top-width", "border-right-width", "border-bottom-width", "border-left-width",
	"border-top-style", "border-right-style", "border-bottom-style", "border-left-style",
	"border-top-color", "border-right-color", "border-bottom-color", "border-left-color",
}

@(private)
default_display :: proc(tag: string) -> Display {
	switch tag {
	case "head", "script", "style", "template", "title", "meta", "link", "base", "noscript":
		// noscript: we have no JS yet, but real browsers with JS enabled hide it too
		return .None
	case "li":
		return .List_Item
	case "table":
		return .Table
	case "thead", "tbody", "tfoot":
		return .Table_Row_Group
	case "tr":
		return .Table_Row
	case "td", "th":
		return .Table_Cell
	case "caption":
		return .Table_Caption
	case "colgroup", "col":
		return .None // column styling is not supported
	case "html", "body", "address", "article", "aside", "blockquote", "dd", "div", "dl", "dt",
	     "fieldset", "figcaption", "figure", "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6",
	     "header", "hr", "main", "nav", "ol", "p", "pre", "section", "ul", "details", "summary":
		return .Block
	}
	return .Inline
}

// Maps a CSS display value as serialized by lexbor to our enum.
// Layout modes we don't support yet fall back to their outer behavior:
// flex/grid act like block, inline-block/inline-flex like inline.
parse_display :: proc(value: string) -> (display: Display, ok: bool) {
	// newer CSS allows two keywords ("block flow"), the first one is the outer display
	outer := strings.trim_space(value)
	if i := strings.index_byte(outer, ' '); i >= 0 {
		outer = outer[:i]
	}
	switch outer {
	case "none":
		return .None, true
	case "list-item":
		return .List_Item, true
	case "flex", "inline-flex":
		return .Flex, true
	case "block", "grid", "flow-root":
		return .Block, true
	case "table", "inline-table":
		return .Table, true
	case "table-row-group", "table-header-group", "table-footer-group":
		return .Table_Row_Group, true
	case "table-row":
		return .Table_Row, true
	case "table-cell":
		return .Table_Cell, true
	case "table-caption":
		return .Table_Caption, true
	case "table-column", "table-column-group":
		return .None, true
	case "inline", "inline-block", "inline-grid", "contents":
		return .Inline, true
	}
	return .Inline, false
}

// list-style-type, or the list-style shorthand ("none", "square inside", ...):
// we look for the type and ignore position and image.
parse_list_style :: proc(value: string) -> (list_style: List_Style, ok: bool) {
	rest := value
	for word in strings.fields_iterator(&rest) {
		switch word {
		case "none":
			return .None, true
		case "disc", "initial":
			return .Disc, true
		case "circle":
			return .Circle, true
		case "square":
			return .Square, true
		case "decimal", "decimal-leading-zero", "lower-alpha", "upper-alpha", "lower-latin",
		     "upper-latin", "lower-roman", "upper-roman", "lower-greek":
			return .Decimal, true
		}
	}
	return .Disc, false
}
