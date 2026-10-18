# What tobrod still renders differently

How we find out what to implement next, and the current list. It comes from two tools that run over the pages in [tools/pages.txt](../tools/pages.txt). The list has twelve real pages: two Wikipedia articles, odin-lang.org, example.com, the first web page at CERN, danluu.com, Hacker News, Lobsters, rust-lang.org, the Python tutorial, MDN and a GitHub repository.

- **`tools/compare.py`** renders every page with Firefox and with tobrod at the size of tobrod's page view (1024 × 732). Firefox runs headless with JavaScript off and a light theme. The report (`screenshots/compare/index.html`) shows both pictures and where they differ. Fonts are rasterized differently, so the percentages are only a rough guide; the pictures show what is missing.
- **`tools/cssreport`** loads the same pages the way tobrod does and counts the CSS that applies to elements but that tobrod ignores or only approximates. The result is a table sorted by how many pages use each property. Properties without a visible effect on a page you only look at, like `transition`, `cursor` or `user-select`, are listed separately. Two more tables cover HTML: visible elements a browser renders in its own way (form controls, SVG, `<details>`, italic `<em>`, monospace `<code>`, ...) and presentational attributes like `bgcolor` or `align`.

```sh
odin build . && python tools/compare.py tools/pages.txt
odin run tools/cssreport -- --replay snapshots @tools/pages.txt
```

The pages are frozen: the first run of `compare.py` records them into `snapshots/` (not in git), later runs and the report replay that recording. `compare.py --refresh` records them again, so the numbers change only then.

## The list (October 2026)

Ordered by how much they change what a page looks like, weighed against how big the step is. The numbers in brackets are pages / elements from the CSS report (12 pages).

### Bugs

- ~~**`<link media="...">` is not evaluated.**~~ Fixed: the `media` attribute of `<link>` and `<style>` is evaluated like an `@media` block. The Python docs used to load their `(prefers-color-scheme: dark)` stylesheet and turn dark.
- ~~**`@import` in stylesheets is not followed.**~~ Fixed. The Python docs load most of their rules with `@import url("basic.css")`; their navigation bar was a bulleted list.

### Text

2. ~~**`text-decoration`** (9 / 4260)~~: done. Underline, overline and line-through, propagated to the text inside, the UA underline of links.
3. ~~**`line-height`** (9 / 1980)~~: done (numbers, lengths, percentages, inherited like in CSS). Not yet from the `font` shorthand.
4. ~~**`font-style: italic`** (5 / 209) and **`font-family`** (9 / 1650)~~: done with Inter Italic and JetBrains Mono: `<code>` and `<pre>` are monospace, `<i>`, `<em>`, `<cite>` italic, and the `font` shorthand is read. Still missing: a serif font (Firefox's default; pages that ask for serif get Inter) and web fonts (`@font-face`).
5. ~~**`white-space`** (8 / 1202)~~: done (`normal`, `nowrap`, `pre`, `pre-wrap`, `pre-line`, `<td nowrap>`); `<pre>` no longer wraps, like in Firefox.
6. ~~**`text-transform`** (6 / 289), **`letter-spacing`** (4 / 296), **`word-break`**/**`overflow-wrap`** (5 / 196)~~: done; words also wrap after a hyphen or slash between letters. Still to do: `text-overflow: ellipsis` (3 / 112).

### Layout

7. ~~**`display: inline-block`** (7 / 1963) and **`inline-flex`** (6 / 128)~~: done. Still missing: **`vertical-align`** for inline content (`top`, `middle`, ...), inline blocks sit on the baseline.
8. ~~**`box-sizing: border-box`** (7 / 251) and **`min-width`** (8 / 154)~~: done.
9. ~~**`calc()`** in lengths (5 pages; margins, widths, heights)~~: done (`+ - * /`, nested, mixed units resolved in the layout). Not yet in `font-size`, and no `min()`/`max()`/`clamp()`.
10. ~~**HTML attributes for presentation**~~: done (`bgcolor`, `align`, `valign`, `width`, `height`, `cellpadding`, `cellspacing`, `border`, `<center>`, `<font color size>`). Hacker News now has its orange bar and layout; what is left there is the vote arrow (a `background-image`) and row heights.
11. **CSS grid** (2 / 70): the page layout of Wikipedia (the table of contents on the left) and MDN.
12. **Negative margins on floats**: the Python docs put their sidebar next to the content with `float: left; margin-left: -100%`; it ends up below the content.
13. ~~**`<details>`** without `open` (2 / 25) and **`<sup>`/`<sub>`** (2 / 105)~~: done. Still open: `<noscript>` (we hide it, but without JavaScript a browser shows it; lexbor would have to parse its content as markup).
14. **`z-index`** (6 / 233), **`position: sticky`** (4 / 6), **`display: contents`**, **`-webkit-box`**.

### Drawing

15. **SVG images**: almost every logo and icon (Wikipedia, odin-lang.org, GitHub, MDN): `<img>` with an SVG source on 7 pages, inline `<svg>` on 3 (128 elements). They need an SVG rasterizer, which means a new library.
16. ~~**`border-radius`** (8 / 2514)~~: done (per corner, also with borders and on inline elements). Not yet: clipping content to the rounded shape (images in rounded cards, round avatars) and elliptical corners (drawn round).
17. **`background-image`** with a raster image, **`background-size`/`-position`/`-repeat`** (5 / 164).
18. **`opacity`** (4 / 367), **`box-shadow`** (6 / 102), **`transform`** (4 / 220), **`mask-image`** (icons, 4 / 286).

### Forms

19. ~~**`<input>` (5 / 12), `<button>` (3 / 28), `<select>`, `<textarea>`**~~: drawn like Firefox draws them (text fields with value or placeholder, buttons, checkboxes, radios, selects with their selected option, textareas, file inputs). Only to look at: nothing can be typed or clicked yet. `range`, `color` and date inputs are drawn as text fields.

### Not visible on a static page

`cursor`, `transition`, `user-select`, `scroll-behavior`, `break-inside`, ... (see the second table of the report).
