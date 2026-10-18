# Contributing to tobrod

Thanks for your interest! tobrod is a toy browser and, first of all, a learning project: the point is to build the parts of a browser step by step and understand how they work. Contributions are welcome in that spirit – small, understandable steps are worth more than large finished solutions.

Please be kind to each other; see the [Code of Conduct](CODE_OF_CONDUCT.md).

## Ways to help

- **Report a page that looks wrong.** Open an issue with the URL, what tobrod shows and what a real browser shows (screenshots help a lot). tobrod has no JavaScript yet, so compare with JavaScript turned off.
- **Pick something from the list.** [docs/rendering-gaps.md](docs/rendering-gaps.md) lists what is still missing, ordered by how much it matters on real pages; the [roadmap](README.md#roadmap) has the bigger stages.
- **Improve the docs**, the tests or the tools in [tools/](tools/).

For anything bigger than a small fix, please open an issue first, so we can talk about the approach before you spend time on it.

## Ground rules

- **No new libraries without talking about it first.** The external parts (libcurl, lexbor, raylib) are bound through small hand-written Odin bindings on purpose. New fonts or other assets need a license that allows redistribution (like the SIL OFL of the fonts in `assets/fonts/`).
- **No third-party content in the repository.** Test pages in [testdata/](testdata/) and pictures in `docs/screenshots/` are made for this project. Recordings of real pages (`snapshots/`) stay local.
- **Keep the dependency direction:** `main` → `browser` → (`ui`, `http`, `dom`, `loader`); `ui` → `layout` → `dom` → `vendor/lexbor`. The UI talks to the browser through callbacks, not imports.

## Getting started

Building is described in the [README](README.md#building). Always run from the repository root, the fonts are loaded from relative paths:

```sh
odin run .
odin check .   # quick type check
```

## Before you open a pull request

1. **Run the tests** of the packages you touched (all of them for larger changes):

   ```sh
   odin test dom
   odin test layout
   odin test http
   odin test loader
   odin test browser
   odin test ui
   odin test vendor/lexbor
   ```

   New behavior gets a test. The layout tests use a fake text measurement, so they need no window and give exact numbers.

2. **Look at the result.** For anything visible, add or extend a page in [testdata/](testdata/) and compare it with Firefox:

   ```sh
   python -m http.server 8765 --bind 127.0.0.1 --directory testdata
   odin build . && python tools/compare.py http://127.0.0.1:8765/styles.html
   ```

   For changes that can affect real pages, compare the pages in [tools/pages.txt](tools/pages.txt) before and after (they are recorded once and replayed offline, see [Measuring progress](README.md#measuring-progress)). Build the old version with `odin build . -out:old.exe` on `main` and pass it with `--tobrod`.

3. **Update the docs** when something user-visible changes: the README (features, roadmap, known limitations) and [docs/rendering-gaps.md](docs/rendering-gaps.md).

## Code style

- Odin's conventions: tabs, `snake_case` procedures (with a component prefix inside a package, like `page_view_render`), `Ada_Case` types, `SCREAMING_SNAKE_CASE` constants.
- One concept per file; packages are folders.
- Comments are short, in English, and explain *why*, not what.
- Errors are returned as `Maybe(Some_Error)`, not panics. Clean up what was already created when something fails halfway.
- Frame-local and short-lived allocations use `context.temp_allocator`.

## Commits and pull requests

- Work on a branch and open a pull request against `main`.
- Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/), with the package as the scope: `feat(layout): …`, `fix(http): …`, `refactor(ui): …`, `docs: …`, `chore: …`.
- In the pull request, say what changed and why, and how you checked it (the template asks for that).

Code you contribute is licensed under the project's [MIT License](LICENSE).
