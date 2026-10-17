tobrod - a toy browser in Odin
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## Dependencies

- [libcurl](https://curl.se) (built from source via git submodule, see Setup)
- [raylib](https://www.raylib.com) (bundled via `vendor:raylib`, no separate download needed)
- [lexbor](https://github.com/lexbor/lexbor)

## Fonts

tobrod ships the [Inter](https://github.com/rsms/inter) font (Regular and Bold) in `assets/fonts/`. The fonts are licensed under the SIL Open Font License 1.1, see [assets/fonts/OFL.txt](assets/fonts/OFL.txt); the MIT license of this project does not apply to them.

## Setup Windows

Requires CMake and Visual Studio Build Tools (for the MSVC linker/compiler) to be installed beforehand.

Run `.\setup.ps1` before building. This builds curl and lexbor from source (statically, with a CRT setting compatible with `vendor:raylib` — Odin's bundled `vendor:curl` conflicts with raylib on Windows, see git history for details). Requires CMake and the Visual Studio Build Tools.

## Setup MacOS

- brew install curl
- brew install mbedtls
- brew install lexbor

# Planned stages

Stage 1 — HTTP Client

- [x] Basic GET requests via self-built libcurl bindings (`vendor/curl`)
- [x] Response headers parsing
- [x] Error handling
- [x] Connection reuse

Stage 2 — Window & UI

- [x] Window creation via vendor:raylib
- [ ] Address bar
   - [x] basic address bar ui
   - [x] basic text rendering for user input
   - [x] triggering http client to call page when hitting enter
   - [ ] harden input by auto adding http when missing -> TODO for later
- [ ] Basic tab management -> TODO for later
- [x] Clickable links (relative URLs resolved via curl's URL API, redirects followed)
- [x] Navigation buttons (back, forward, reload) with session history; Alt+←/→, F5/Ctrl+R

Stage 3 — Page View Renderer (Raw Text)

- [x] Text rendering in page view
- [x] Text wrapping
- [x] Scrolling
   - [x] scrolling should only be possible if the content exceeds the view

Stage 4 — HTML & CSS Parsing

- [ ] Bind lexbor for HTML parsing
   - [x] create/parse/destroy document (smoke-tested)
   - [x] traverse DOM nodes (first_child, next sibling)
   - [x] read node/element data (tag name, text content, attributes)
- [x] Build a DOM tree from parsed HTML
- [x] Show HTML pages as plain text (hidden elements, whitespace collapsing, block line breaks)
- [x] CSS parsing and CSSOM construction (via lexbor's css/style modules)
- [x] Selector matching and cascade (via lexbor: specificity, `!important`, inline styles)
- [x] External stylesheets (`<link rel="stylesheet">`, render-blocking)
- [x] `@media` queries (evaluated for the viewport at load time)
- [x] `visibility`, `list-style`, `position: absolute/fixed` (taken out of the flow, not placed yet)
- [x] CSS custom properties (`var()`, inherited, fallbacks, own cascade decision via specificity)
- [ ] Use computed styles in our DOM and when rendering
   - [x] `display` (UA defaults + CSS, `display: none` hides elements)
   - [x] inheritance and defaults for other properties (color, font-size, font-weight)
   - [x] render text with its style (font size, bold, color)
      - [x] layout: styled text runs with line wrapping, margins, lists (package `layout`)
      - [x] draw the runs in the ui (regular and bold Inter)
   - [x] more layout
      - [x] box model: margin, padding, width, max-width, `margin: auto` centering, background colors
      - [x] `text-align`, borders, `vw`/`vh` units
      - [x] images
         - [x] layout: size from CSS/attributes/natural size, inline placement, placeholder, links
         - [x] load (resource queue in the loader), decode (raylib: PNG, JPG, GIF, BMP, QOI) and draw
      - [x] tables: automatic column widths (min/max-content), colspan, captions, anonymous rows/cells, vertical-align, border-collapse
      - [x] floats: shrink-to-fit width, text flowing around them, clear

Stage 5 - Threads
- [x] Run http requests in own thread (package `loader`: worker thread, also parses)
- [x] how to send results back to ui? -> request/result queue with mutex + condition variable, ui polls once per frame
- [x] http client is not thread safe... what to do? -> the worker owns its own client; cancelling via an atomic abort flag
- [x] use the loader in the browser + loading indicator (animated bar, stop button, Escape)

Stage 6 — JavaScript Engine

- [ ] Bind QuickJS as the JavaScript engine
- [ ] Connect JS engine to the DOM
- [ ] Basic DOM manipulation via JavaScript
