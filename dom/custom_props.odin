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
// Custom properties are inherited. An element that declares none shares the
// map of its parent; one that does gets a copy with its own values on top.

Custom_Props :: map[string]string

// What the walk found on one element.
@(private)
Declared :: struct {
	customs:    map[string]Spec_Value, // --name -> raw value
	var_values: map[string]Spec_Value, // property -> raw value containing var()
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
		var_values = make(map[string]Spec_Value, allocator = context.temp_allocator),
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
			value := serialize_value(declaration)
			if contains_var(value) {
				if old, ok := d.var_values[name]; !ok || spec >= old.spec {
					d.var_values[name] = {value, spec}
				}
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

// The var() declarations that beat the normal ones, with var() substituted:
// property -> value, ready for apply_declaration.
@(private)
winning_var_declarations :: proc(declared: ^Declared, props: ^Custom_Props) -> map[string]string {
	result := make(map[string]string, allocator = context.temp_allocator)
	for name, sv in declared.var_values {
		if sv.spec < declared.plain_spec[name] {
			continue // a normal declaration with higher specificity wins
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
