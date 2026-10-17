package dom

import "core:mem"
import "core:strings"
import lxb "../vendor/lexbor"

// A report of the CSS a page uses that we don't support (yet), to find out
// what to implement next (tools/cssreport). parse fills it if one is given;
// the browser doesn't pass one.
//
// It counts per element, after the cascade matched the rules:
// - properties we don't read at all (line-height, white-space, transform, ...)
// - values of properties we do read, but only approximate or ignore:
//   display modes we fall back from (grid, inline-block, ...), sticky, and
//   lengths with calc()
Css_Report :: struct {
	allocator:  mem.Allocator,
	properties: map[string]int, // property -> number of elements it applies to
	values:     map[string]int, // "display: grid" -> number of elements
}

css_report_init :: proc(allocator := context.allocator) -> Css_Report {
	return {
		allocator  = allocator,
		properties = make(map[string]int, allocator = allocator),
		values     = make(map[string]int, allocator = allocator),
	}
}

css_report_destroy :: proc(r: ^Css_Report) {
	for key in r.properties {
		delete(key, r.allocator)
	}
	for key in r.values {
		delete(key, r.allocator)
	}
	delete(r.properties)
	delete(r.values)
}

@(private)
report_count :: proc(r: ^Css_Report, m: ^map[string]int, key: string) {
	if key in m {
		m[key] += 1
	} else {
		m[strings.clone(key, r.allocator)] = 1
	}
}

// Display values we lay out exactly as CSS says; others fall back to their
// outer behavior (see parse_display).
@(private)
SUPPORTED_DISPLAY :: []string {
	"none", "block", "inline", "list-item", "flex", "flow-root",
	"table", "table-row-group", "table-header-group", "table-footer-group",
	"table-row", "table-cell", "table-caption",
}

// Called by compute_style with what the walk found on one element.
@(private)
report_element :: proc(r: ^Css_Report, element: ^lxb.Dom_Element, declared: ^Declared) {
	supported :: proc(property: string) -> bool {
		for p in STYLE_PROPERTIES {
			if p == property {
				return true
			}
		}
		return false
	}
	check :: proc(r: ^Css_Report, element: ^lxb.Dom_Element, declared: ^Declared, property: string) {
		if !supported(property) {
			report_count(r, &r.properties, property)
			return
		}
		// the winning typed value, or the raw text lexbor couldn't parse (calc(), var())
		value, ok := lxb.element_style(element, property, context.temp_allocator)
		if raw, has_raw := declared.raw_values[property]; has_raw && (!ok || raw.spec >= declared.plain_spec[property]) {
			value, ok = raw.value, true
		}
		if !ok {
			return
		}
		switch {
		case property == "display":
			outer := value
			if i := strings.index_byte(outer, ' '); i >= 0 {
				outer = outer[:i]
			}
			for d in SUPPORTED_DISPLAY {
				if d == outer {
					return
				}
			}
			report_count(r, &r.values, strings.concatenate({"display: ", outer}, context.temp_allocator))
		case property == "position" && value == "sticky":
			report_count(r, &r.values, "position: sticky")
		case strings.contains(value, "calc("):
			report_count(r, &r.values, strings.concatenate({"calc() in ", property}, context.temp_allocator))
		}
	}
	for property in declared.plain_spec {
		check(r, element, declared, property)
	}
	for property in declared.raw_values {
		if !(property in declared.plain_spec) {
			check(r, element, declared, property)
		}
	}
}
