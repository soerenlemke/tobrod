tobrod - a toy browser in Odin
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## Dependencies

- [libcurl](https://curl.se) (built from source via git submodule, see Setup)
- [raylib](https://www.raylib.com) (bundled via `vendor:raylib`, no separate download needed)
- [lexbor](https://github.com/lexbor/lexbor)

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
- [ ] Navigation buttons (back, forward, reload) -> TODO for later

Stage 3 — Page View Renderer (Raw Text)

- [x] Text rendering in page view
- [x] Text wrapping
- [x] Scrolling
   - [x] scrolling should only be possible if the content exceeds the view

Stage 4 — HTML & CSS Parsing

- [ ] Bind lexbor for HTML parsing
   - [x] create/parse/destroy document (smoke-tested)
   - [x] traverse DOM nodes (first_child, next sibling)
   - [ ] read node/element data (tag name, text content, attributes)
- [ ] Build a DOM tree from parsed HTML
- [ ] CSS parsing and CSSOM construction
- [ ] Selector matching

Stage 5 - Threads
- [ ] Run http requests in own thread
- [ ] how to send results back to ui?
- [ ] http client is not thread safe... what to do?

Stage 6 — JavaScript Engine

- [ ] Bind QuickJS as the JavaScript engine
- [ ] Connect JS engine to the DOM
- [ ] Basic DOM manipulation via JavaScript
