tobrod - a toy browser in Odin
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## Dependencies

- [libcurl](https://curl.se)
- [SDL3](https://libsdl.org)

## Setup Windows
Run `.\setup.ps1` before building.

## Setup MacOS
- brew install sdl3
- brew install curl
- brew install mbedtls

# Planned stages

Stage 1 — HTTP Client

 - [x] Basic GET requests via vendor:curl
 - [x] Response headers parsing
 - [x] Error handling
 - [x] Connection reuse

Stage 2 — Window & UI

 - [x] Window creation via vendor:sdl3
 - [ ] Address bar
 - [ ] Basic tab management
 - [ ] Navigation buttons (back, forward, reload)

Stage 3 — HTML & CSS Parsing

 - [ ] Bind lexbor for HTML parsing
 - [ ] Build a DOM tree from parsed HTML
 - [ ] CSS parsing and CSSOM construction
 - [ ] Selector matching

Stage 4 — Rendering

 - [ ] Font loading and rendering via vendor:stb
 - [ ] Basic text layout
 - [ ] Box model implementation
 - [ ] OpenGL-based paint layer via vendor:OpenGL

Stage 5 — JavaScript Engine

 - [ ] Bind QuickJS as the JavaScript engine
 - [ ] Connect JS engine to the DOM
 - [ ] Basic DOM manipulation via JavaScript
