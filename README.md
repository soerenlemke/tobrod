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
- brew install sdl3_ttf

# Planned stages

Stage 1 — HTTP Client

- [x] Basic GET requests via vendor:curl
- [x] Response headers parsing
- [x] Error handling
- [x] Connection reuse

Stage 2 — Window & UI

- [x] Window creation via vendor:sdl3
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
- [ ] Build a DOM tree from parsed HTML
- [ ] CSS parsing and CSSOM construction
- [ ] Selector matching

Stage 5 - Threads
- [ ] Run http requests in own thread
- [ ] how to send results back to ui? -> SDL_PushEvent?
- [ ] http client is not thread safe... what to do?

Stage 6 — JavaScript Engine

- [ ] Bind QuickJS as the JavaScript engine
- [ ] Connect JS engine to the DOM
- [ ] Basic DOM manipulation via JavaScript
