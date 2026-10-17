package cssreport

// Loads pages like tobrod does (HTML + external stylesheets, @media for a
// 1024 x 732 page view) and lists the CSS they use that tobrod doesn't
// support, sorted by how many pages use it. A guide for what to implement next.
//
//   odin run tools/cssreport -- de.wikipedia.org/wiki/Webbrowser odin-lang.org
//   odin run tools/cssreport -- @tools/pages.txt     (one URL per line)

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import "../../dom"
import "../../http"

// the page view of tobrod's default window (1024 x 768 minus the address bar)
MEDIA :: dom.Media_Env{1024, 732}

Fetch :: struct {
	client: ^http.Client,
	base:   string,
}

// Properties without a visible effect on a page that is only looked at (no
// animation, no hover, no text selection, no focus, no printing): listed
// separately.
NO_VISIBLE_EFFECT :: []string {
	"transition", "transition-property", "transition-duration", "transition-timing-function", "transition-delay",
	"animation", "animation-name", "animation-duration", "animation-timing-function", "animation-delay",
	"animation-iteration-count", "animation-direction", "animation-fill-mode", "animation-play-state",
	"cursor", "user-select", "-webkit-user-select", "-moz-user-select", "-ms-user-select", "pointer-events",
	"will-change", "touch-action", "scroll-behavior", "scroll-margin-top", "scroll-padding-top", "speak",
	"-webkit-tap-highlight-color", "-webkit-touch-callout", "content-visibility", "contain", "resize",
	"overscroll-behavior", "-webkit-font-smoothing", "-moz-osx-font-smoothing", "text-rendering",
	"font-feature-settings", "font-variant-ligatures", "print-color-adjust", "-webkit-print-color-adjust",
	"color-scheme", "forced-color-adjust", "accent-color", "caret-color", "orphans", "widows",
	"page-break-inside", "page-break-after", "page-break-before", "break-inside", "break-after", "break-before",
}

Row :: struct {
	key:             string,
	pages, elements: int,
}

main :: proc() {
	urls := make([dynamic]string)
	for arg in os.args[1:] {
		if strings.has_prefix(arg, "@") {
			data, read_err := os.read_entire_file(arg[1:], context.allocator)
			if read_err != nil {
				fmt.eprintln("cannot read", arg[1:])
				os.exit(1)
			}
			for line in strings.split_lines(string(data)) {
				line := strings.trim_space(line)
				if line != "" && !strings.has_prefix(line, "#") {
					append(&urls, line)
				}
			}
		} else {
			append(&urls, arg)
		}
	}
	if len(urls) == 0 {
		fmt.eprintln("usage: cssreport <url>... | @file")
		os.exit(1)
	}

	if err, failed := http.global_init().?; failed {
		fmt.eprintln(err.message)
		os.exit(1)
	}
	client, err := http.init()
	if e, failed := err.?; failed {
		fmt.eprintln(e.message)
		os.exit(1)
	}

	// key -> pages using it / elements over all pages
	pages := make(map[string]int)
	elements := make(map[string]int)
	loaded := 0
	for url in urls {
		url := http.complete_url(url, context.temp_allocator)
		response, get_err := http.get(&client, url)
		if e, failed := get_err.?; failed {
			fmt.eprintfln("%s: %s", url, e.message)
			continue
		}
		base := strings.clone(response.url, context.temp_allocator)
		html := strings.clone(response.body, context.temp_allocator)

		report := dom.css_report_init(context.temp_allocator)
		fetch := Fetch{&client, base}
		doc, parse_err := dom.parse(html, {load = load_stylesheet, ctx = &fetch}, MEDIA, &report)
		if e, failed := parse_err.?; failed {
			fmt.eprintfln("%s: %s", url, e.message)
			continue
		}
		dom.destroy(doc)
		loaded += 1
		fmt.eprintfln("%s: %d unsupported properties, %d approximated values", base, len(report.properties), len(report.values))

		add :: proc(pages, elements: ^map[string]int, key: string, count: int) {
			if !(key in pages) {
				key := strings.clone(key)
				pages[key] = 0
				elements[key] = 0
			}
			pages[key] += 1
			elements[key] += count
		}
		for key, count in report.properties {
			add(&pages, &elements, key, count)
		}
		for key, count in report.values {
			add(&pages, &elements, strings.concatenate({"= ", key}, context.temp_allocator), count)
		}
		free_all(context.temp_allocator)
	}

	rows := make([dynamic]Row)
	for key, n in pages {
		append(&rows, Row{key, n, elements[key]})
	}
	slice.sort_by(rows[:], proc(a, b: Row) -> bool {
		if a.pages != b.pages {
			return a.pages > b.pages
		}
		if a.elements != b.elements {
			return a.elements > b.elements
		}
		return a.key < b.key
	})

	visible := make([dynamic]Row)
	invisible := make([dynamic]Row)
	for row in rows {
		append(&invisible if slice.contains(NO_VISIBLE_EFFECT, row.key) else &visible, row)
	}

	fmt.printfln("# Unsupported CSS on %d pages\n", loaded)
	fmt.println("Properties tobrod doesn't read, and values it only approximates,")
	fmt.println("counted per element the cascade applies them to.\n")
	print_table(visible[:])
	fmt.println("\n## Without a visible effect on a static page\n")
	print_table(invisible[:])
}

print_table :: proc(rows: []Row) {
	fmt.println("| CSS | pages | elements |")
	fmt.println("|---|---:|---:|")
	for row in rows {
		fmt.printfln("| `%s` | %d | %d |", strings.trim_prefix(row.key, "= "), row.pages, row.elements)
	}
}

// dom.Stylesheet_Loader: like the loader's.
load_stylesheet :: proc(ctx: rawptr, href, base: string) -> (css, url: string, ok: bool) {
	fetch := cast(^Fetch)ctx
	resolved := http.resolve_url(base if base != "" else fetch.base, href, context.temp_allocator) or_return
	if !http.is_loadable_url(resolved) {
		return "", "", false
	}
	response, err := http.get(fetch.client, resolved)
	if _, failed := err.?; failed {
		return "", "", false
	}
	// valid until the next request; dom.parse copies what it needs
	return response.body, response.url, true
}
