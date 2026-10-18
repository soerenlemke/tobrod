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

### Done since the last measurement

- ~~Logical properties~~ (`margin-inline-start` 4 / 181, `padding-block` 3 / 1617, `margin-inline-end`, `padding-inline-start`, `inline-size`, ...): read as the physical sides (text is always horizontal, left to right).

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
11. ~~**CSS grid** (2 / 70)~~: done (track lists with `fr`, `minmax()`, `repeat()` incl. `auto-fill`, named areas, line and span placement, auto placement row by row, gaps, `justify-*`/`align-*`), and `display: contents` for the children of flex and grid containers. MDN now has its sidebar and content column. Wikipedia only uses grid for its page layout from 1120px on, wider than our window. Still open: `fr` rows (a container height), `grid-auto-flow: column`/`dense`, `order`.
12. **Negative margins on floats**: the Python docs put their sidebar next to the content with `float: left; margin-left: -100%`; it ends up below the content.
13. ~~**`<details>`** without `open` (2 / 25) and **`<sup>`/`<sub>`** (2 / 105)~~: done. Still open: `<noscript>` (we hide it, but without JavaScript a browser shows it; lexbor would have to parse its content as markup).
14. ~~**`z-index`** (6 / 233)~~: done (layers in paint order, stacking contexts; not for positioned inline elements). Still open: **`position: sticky`** (4 / 6), **`display: contents`**, **`-webkit-box`**.

### Drawing

15. **SVG**: ~~`<img>` with an SVG source (7 pages)~~ is drawn by our own renderer (package `svg`: shapes and paths filled with a color, transforms, viewBox; Wikipedia's wordmark, the Odin and Rust logos). Strokes are drawn too (width, caps, joins, miter limit, dashes). ~~Inline `<svg>` (3 pages / 128 elements)~~ is drawn too: GitHub's icons and logo, MDN's and odin-lang.org's icons. Still open: `fill`/`stroke` from the page's CSS (MDN's logo is black instead of blue), `<use>`, real gradients, SVG as a background image. The Odin logo overlaps the title below it.
16. ~~**`border-radius`** (8 / 2514)~~: done (per corner, also with borders and on inline elements). Not yet: clipping content to the rounded shape (images in rounded cards, round avatars) and elliptical corners (drawn round).
17. ~~**`background-image`**, **`background-size`/`-position`/`-repeat`** (5 / 164)~~: done for images (raster and SVG, first layer), sharing the code with `mask-image`; `url()`s in stylesheets are resolved against the stylesheet. Hacker News has its vote arrows, Lobsters its logo. Still open: gradients (drawn as nothing), clipping to rounded corners, `background-origin`/`-clip`/`-attachment`, a background image on `html`/`body` covering the whole page (it stays in the body's box).
18. ~~**`opacity`** (4 / 367)~~: done. A block with opacity is drawn as a group (into a texture of its own, then faded), so text on a background stays readable; nested opacity and inline elements fade their colors instead. It also hides what pages hide with `opacity: 0`: odin-lang.org's carousel arrows and card texts, Wikipedia's invisible checkboxes over its menu buttons. ~~**`mask-image`** (icons, 4 / 286)~~: done for images (`url()`, also `data:` URLs, size, position, repeat): Wikipedia's menu, search and language icons, MDN's badges. Gradient masks (fading edges on odin-lang.org and GitHub) are drawn without the mask, and the mask only cuts the element's own background, not its content. Still open: **`box-shadow`** (6 / 102), **`transform`** (4 / 220).

### Forms

19. ~~**`<input>` (5 / 12), `<button>` (3 / 28), `<select>`, `<textarea>`**~~: drawn like Firefox draws them (text fields with value or placeholder, buttons, checkboxes, radios, selects with their selected option, textareas, file inputs). Only to look at: nothing can be typed or clicked yet. `range`, `color` and date inputs are drawn as text fields.

### Not visible on a static page

`cursor`, `transition`, `user-select`, `scroll-behavior`, `break-inside`, ... (see the second table of the report).
