package dom

import "base:runtime"
import "core:strings"
import lxb "../vendor/lexbor"

// CSS custom properties ("variables"): --name: value and var(--name, fallback).
//
// What lexbor does (found with a probe): it knows custom properties and keeps
// declarations that use var() with their raw text, but its cascade lets a plain
// "color: red" beat a later "color: var(--main)" in the same rule. So we walk
// all declarations of an element ourselves, with their specificity, and decide
// for those cases: a var() declaration wins when its specificity is at least as
// high (on a tie it is usually the later one: `color: #000; color: var(--x)`).
//
// The same goes for any other value lexbor can't parse into a typed value
// ("undef"), e.g. `clear: both`, which lexbor doesn't know: we give our own
// parsers a chance at the raw text.
//
// Custom properties are inherited. An element that declares none shares the
// map of its parent; one that does gets a copy with its own values on top.

Custom_Props :: map[string]string

// What the walk found on one element.
@(private)
Declared :: struct {
	customs:    map[string]Spec_Value, // --name -> raw value
	raw_values: map[string]Spec_Value, // property -> raw value lexbor couldn't parse (often with var())
	plain_spec: map[string]u32,        // property -> highest specificity of normal declarations
}

@(private)
Spec_Value :: struct {
	value: string,
	spec:  u32,
}

// Collects the declarations of an element. Everything lives in the temp allocator.
@(private)
walk_declarations :: proc(element: ^lxb.Dom_Element) -> Declared {
	d := Declared {
		customs    = make(map[string]Spec_Value, allocator = context.temp_allocator),
		raw_values = make(map[string]Spec_Value, allocator = context.temp_allocator),
		plain_spec = make(map[string]u32, allocator = context.temp_allocator),
	}
	Walk_Ctx :: struct {
		ctx:      runtime.Context,
		declared: ^Declared,
	}
	walk_ctx := Walk_Ctx{context, &d}

	callback :: proc "c" (element: ^lxb.Dom_Element, declaration: ^lxb.Css_Rule_Declaration, ctx: rawptr, spec: u32, is_weak: bool) -> lxb.Status {
		walk_ctx := cast(^Walk_Ctx)ctx
		context = walk_ctx.ctx
		d := walk_ctx.declared

		name_b := strings.builder_make(context.temp_allocator)
		lxb.lxb_css_property_serialize_name(declaration.value, declaration.type, write_builder, &name_b)
		name := strings.to_string(name_b)

		if strings.has_prefix(name, "--") {
			if old, ok := d.customs[name]; !ok || spec >= old.spec {
				d.customs[name] = {serialize_value(declaration), spec}
			}
			return lxb.STATUS_OK
		}
		if declaration.type == UNDEF_PROPERTY {
			if old, ok := d.raw_values[name]; !ok || spec >= old.spec {
				d.raw_values[name] = {serialize_value(declaration), spec}
			}
			return lxb.STATUS_OK
		}
		d.plain_spec[name] = max(d.plain_spec[name], spec)
		return lxb.STATUS_OK
	}

	lxb.lxb_dom_element_style_walk(element, callback, &walk_ctx, true)
	return d
}

// lexbor's type id for a declaration it could not parse into a typed value
// (LXB_CSS_PROPERTY__UNDEF); declarations with var() end up as this.
@(private)
UNDEF_PROPERTY :: 0

@(private)
serialize_value :: proc(declaration: ^lxb.Css_Rule_Declaration) -> string {
	b := strings.builder_make(context.temp_allocator)
	lxb.lxb_css_property_serialize(declaration.value, declaration.type, write_builder, &b)
	return strings.to_string(b)
}

@(private)
write_builder :: proc "c" (data: [^]u8, len: uint, ctx: rawptr) -> lxb.Status {
	b := cast(^strings.Builder)ctx
	context = runtime.default_context()
	strings.write_string(b, strings.string_from_ptr(data, int(len)))
	return lxb.STATUS_OK
}

// The custom properties of an element: the inherited ones plus its own.
// Values are stored with their var() already substituted, like the CSS spec
// does for the computed value of a custom property.
@(private)
element_custom_props :: proc(inherited: ^Custom_Props, declared: ^Declared) -> ^Custom_Props {
	if len(declared.customs) == 0 {
		return inherited
	}
	props := new(Custom_Props, context.temp_allocator)
	props^ = make(Custom_Props, len(inherited) + len(declared.customs), context.temp_allocator)
	for name, value in inherited {
		props[name] = value
	}
	// first the raw values, so custom properties can refer to each other
	for name, sv in declared.customs {
		props[name] = sv.value
	}
	for name, sv in declared.customs {
		if contains_var(sv.value) {
			if resolved, ok := substitute_vars(sv.value, props); ok {
				props[name] = resolved
			} else {
				delete_key(props, name) // invalid at computed-value time: as if unset
			}
		}
	}
	return props
}

// The raw declarations that beat the typed ones, with var() substituted:
// property -> value, to apply on top of lexbor's typed value (so a raw value
// our parsers reject leaves the typed one in place).
@(private)
winning_raw_declarations :: proc(declared: ^Declared, props: ^Custom_Props) -> map[string]string {
	result := make(map[string]string, allocator = context.temp_allocator)
	for name, sv in declared.raw_values {
		if sv.spec < declared.plain_spec[name] {
			continue // a normal declaration with higher specificity wins
		}
		if !contains_var(sv.value) {
			result[name] = strings.to_lower(strings.trim_space(sv.value), context.temp_allocator)
			continue
		}
		if value, ok := substitute_vars(sv.value, props); ok {
			// our value parsers expect lexbor's lowercase serialization
			result[name] = strings.to_lower(strings.trim_space(value), context.temp_allocator)
		} else {
			// it won the cascade but is invalid: CSS then treats the property as
			// "unset" (inherited value or initial), not as the losing declaration
			result[name] = "unset"
		}
	}
	return result
}

// Replaces every var(--name) / var(--name, fallback) in value. Fails if a
// variable is missing and has no fallback (the declaration is then invalid).
substitute_vars :: proc(value: string, props: ^Custom_Props, depth := 0) -> (result: string, ok: bool) {
	if depth > 16 {
		return "", false // a cycle like --a: var(--b); --b: var(--a)
	}
	b := strings.builder_make(context.temp_allocator)
	rest := value
	for {
		start := index_var(rest)
		if start < 0 {
			strings.write_string(&b, rest)
			break
		}
		strings.write_string(&b, rest[:start])

		open := start + len("var(")
		close := matching_paren(rest, open - 1)
		if close < 0 {
			return "", false
		}
		inside := rest[open:close]

		name, fallback := inside, ""
		has_fallback := false
		if comma := index_outside_parens(inside, ','); comma >= 0 {
			name = inside[:comma]
			fallback = inside[comma + 1:]
			has_fallback = true
		}
		name = strings.trim_space(name)

		replacement: string
		if v, found := props[name]; found {
			replacement = v
		} else if has_fallback {
			replacement = strings.trim_space(fallback)
		} else {
			return "", false
		}
		// the replacement may contain var() itself
		replacement = substitute_vars(replacement, props, depth + 1) or_return
		strings.write_string(&b, replacement)
		rest = rest[close + 1:]
	}
	return strings.to_string(b), true
}

@(private)
contains_var :: proc(value: string) -> bool {
	return index_var(value) >= 0
}

// Index of "var(" (any case), -1 if there is none.
@(private)
index_var :: proc(s: string) -> int {
	for i := 0; i + 4 <= len(s); i += 1 {
		if (s[i] == 'v' || s[i] == 'V') && strings.equal_fold(s[i:i + 4], "var(") {
			// not the end of another name like "somevar("
			if i == 0 || !is_name_char(s[i - 1]) {
				return i
			}
		}
	}
	return -1
}

@(private)
is_name_char :: proc(c: u8) -> bool {
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-' || c == '_'
}

// Index of the ) that closes the ( at open, -1 if it is missing.
@(private)
matching_paren :: proc(s: string, open: int) -> int {
	depth := 0
	for i := open; i < len(s); i += 1 {
		switch s[i] {
		case '(':
			depth += 1
		case ')':
			depth -= 1
			if depth == 0 {
				return i
			}
		}
	}
	return -1
}

@(private)
index_outside_parens :: proc(s: string, c: u8) -> int {
	depth := 0
	for i := 0; i < len(s); i += 1 {
		switch s[i] {
		case '(':
			depth += 1
		case ')':
			depth -= 1
		case:
			if s[i] == c && depth == 0 {
				return i
			}
		}
	}
	return -1
}

// The specificity of the winning declaration of a property on the element
// (0 if none). lexbor gives us only the winning value, the walk the rest.
@(private)
declared_spec :: proc(d: ^Declared, property: string) -> (spec: u32, ok: bool) {
	if s, found := d.plain_spec[property]; found {
		spec, ok = s, true
	}
	if raw, found := d.raw_values[property]; found {
		spec, ok = max(spec, raw.spec), true
	}
	return
}

// The shorthands that also set a longhand, from the closest to the widest
// ("" = no more).
@(private)
shorthands_of :: proc(property: string) -> [5]string {
	switch property {
	case "font-size", "font-weight", "line-height", "font-family", "font-style":
		return {0 = "font"}
	case "list-style-type", "list-style-position":
		return {0 = "list-style"}
	case "margin-top", "margin-right", "margin-bottom", "margin-left":
		return {0 = "margin"}
	case "padding-top", "padding-right", "padding-bottom", "padding-left":
		return {0 = "padding"}
	case "background-color":
		return {0 = "background"}
	case "top", "right", "bottom", "left":
		return {0 = "inset"}
	case "overflow-x", "overflow-y":
		return {0 = "overflow"}
	case "row-gap", "column-gap":
		return {0 = "gap"}
	case "flex-grow", "flex-shrink", "flex-basis":
		return {0 = "flex"}
	case "flex-direction", "flex-wrap":
		return {0 = "flex-flow"}
	case "text-decoration-line", "text-decoration-color":
		return {0 = "text-decoration"}
	case "border-width", "border-style", "border-color", "border-top", "border-right", "border-bottom", "border-left":
		return {0 = "border"}
	case "border-top-width", "border-top-style", "border-top-color":
		return {"border-top", "border-width", "border-style", "border-color", "border"}
	case "border-right-width", "border-right-style", "border-right-color":
		return {"border-right", "border-width", "border-style", "border-color", "border"}
	case "border-bottom-width", "border-bottom-style", "border-bottom-color":
		return {"border-bottom", "border-width", "border-style", "border-color", "border"}
	case "border-left-width", "border-left-style", "border-left-color":
		return {"border-left", "border-width", "border-style", "border-color", "border"}
	}
	return {}
}

// Whether a shorthand with a higher specificity than this longhand was
// declared on the element; it was applied before, so the longhand must not
// overwrite it.
@(private)
loses_to_shorthand :: proc(d: ^Declared, property: string) -> bool {
	own := declared_spec(d, property) or_return
	for shorthand in shorthands_of(property) {
		if shorthand == "" {
			break
		}
		if spec, ok := declared_spec(d, shorthand); ok && spec > own {
			return true
		}
	}
	return false
}
