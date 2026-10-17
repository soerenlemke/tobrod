# CLAUDE.md – tobrod

**tobrod** ist ein Toy-Browser in [Odin](https://odin-lang.org). Er ist ein Lernprojekt: Ziel ist, die Bausteine eines Browsers (HTTP, Fenster/UI, Rendering, HTML/CSS-Parsing, Threads, JS) Schritt für Schritt selbst zu bauen. Externe C-Bibliotheken werden über eigene, schlanke Odin-Bindings angebunden. Lizenz: MIT.

Die Roadmap mit dem aktuellen Fortschritt steht in [README.md](README.md) („Planned stages“). Halte diese Checkliste aktuell, wenn ein Punkt erledigt ist.

## Zusammenarbeit

- Kommunikation mit mir auf Deutsch; Code, Kommentare und Commit-Messages auf Englisch.
- Commits im Conventional-Commits-Stil, wie in der History: `feat(ui): …`, `fix(http): …`, `refactor(ui): …`, `chore: …`. Der Scope ist das Package (`ui`, `http`, `lexbor`, …).
- Größere Umbauten auf einem eigenen Branch, dann PR nach `main` (siehe PR #1 `replace-sdl-with-raylib`).
- Es geht ums Lernen: lieber kleine, nachvollziehbare Schritte und Erklärungen als große fertige Lösungen. Keine zusätzlichen Libraries einführen, ohne das vorher abzusprechen.

## Build, Run, Test

Toolchain: Odin `dev-2026-09` (über Homebrew unter `/opt/homebrew/bin/odin`). Editor-Support über OLS ([ols.json](ols.json)).

```sh
odin run .                 # bauen und starten (aus dem Repo-Root!)
odin build .               # nur bauen
odin check .               # nur Typecheck, schnell
odin test vendor/lexbor    # lexbor-Bindings
odin test dom              # eigener DOM-Baum
odin test http             # Header-Parsing, URL-Auflösung
odin test browser          # History
odin test loader           # Worker-Thread, mit eigenem lokalen Test-HTTP-Server (~5 s)
odin test ui               # Bildformat-Erkennung
odin test layout           # Layout (mit Fake-Textmessung, ohne Fenster)
```

**Immer aus dem Repo-Root starten**: Die Fonts werden über relative Pfade (`assets/fonts/Inter_18pt-Regular.ttf`, `assets/fonts/Inter-Bold.ttf`) geladen ([ui/fonts.odin](ui/fonts.odin)).

Stand 2026-10-17 auf macOS und Windows (Odin `dev-2026-05`, nach `setup.ps1`): `odin check .`, `odin build .` und `odin test vendor/lexbor` laufen erfolgreich durch.

### Visuelle Tests (Testmodus)

`tobrod` hat zwei Kommandozeilen-Optionen (geparst mit `core:flags`, Unix-Stil):

- `--url <url>` lädt die URL direkt beim Start (wie Eingabe in der Adressleiste + Enter).
- `--scroll <px>` (nur mit `--screenshot`): scrollt nach dem Laden so weit nach unten, bevor das Bild gemacht wird – zum Prüfen von Stellen weiter unten auf einer Seite.
- `--screenshot <pfad>` wartet, bis die Seite geladen ist (und mindestens `SCREENSHOT_AFTER_FRAMES` Frames), speichert das Fenster als PNG und beendet sich. Ladebalken/Stopp-Button sind deshalb auf Screenshots nie zu sehen. Exit-Code 1, wenn das Bild nicht geschrieben werden kann.

Lokale Fixtures liegen in [testdata/](testdata/) (`hello.txt`, `utf8.txt`, `long.txt`, `index.html`, `styles.html` – Überschriften, Fett, Farben, Größen, Listen, `pre`, `br`; `boxes.html` – Box-Modell: zentrierte Karten, Padding, Hintergründe, Rahmen, `<hr>`, `text-align`, `width: 50%`; `tables.html` – Datentabelle mit zusammengefallenen Rahmen, Infobox mit `colspan`, Caption; `floats.html` – Infobox rechts, Bild links, Text drumherum, `clear`; `images.html` – Bildgrößen, -platzierung und -laden; die Bilder unter `testdata/images/` sind selbst erzeugt (PIL), also ohne fremde Lizenz):

```sh
python3 -m http.server 8765 --bind 127.0.0.1 --directory testdata   # in eigenem Terminal
odin build . && mkdir -p screenshots
./tobrod --url http://127.0.0.1:8765/utf8.txt --screenshot screenshots/utf8.png
```

`screenshots/` und das Binary `tobrod` sind in `.gitignore`.

### Abhängigkeiten pro Plattform

| Lib | macOS | Windows | Linux |
|---|---|---|---|
| libcurl | `brew install curl mbedtls`, gelinkt als `system:curl` + mbedtls + zlib + `SystemConfiguration.framework` | statisch aus Submodul `vendor/curl-src` (curl-8_14_0) gebaut via [setup.ps1](setup.ps1), Schannel für TLS, `/MD`-CRT | `system:curl` + mbedtls + zlib (ungetestet) |
| raylib | `vendor:raylib` (mit Odin ausgeliefert) | dito | dito |
| lexbor | `brew install lexbor`, `system:lexbor` | statisch aus Submodul `vendor/lexbor-src` (v3.0.1) gebaut via [setup.ps1](setup.ps1), `/MD`-CRT, `/NODEFAULTLIB:libcmt` | `system:lexbor` (ungetestet) |

**Warum curl selbst gebaut wird (Windows):** Odins `vendor:curl` bringt eine Lib mit, deren CRT-Einstellung mit `vendor:raylib` kollidiert. Deshalb liegt eine Kopie der Odin-curl-Bindings unter [vendor/curl/](vendor/curl/) (Package `vendor_curl`), die auf Windows gegen `vendor/curl-src/build/lib/Release/libcurl.lib` linkt. `setup.ps1` braucht CMake und die VS Build Tools (Generator `"Visual Studio 18 2026"`). Build-Artefakte (`vendor/curl-src/build/`, `vendor/lexbor-src/build/`, `vendor/curl/lib/`, `*.exe`, `*.dll`) sind in `.gitignore`.

## Projektstruktur

```
main.odin               Einstiegspunkt: CLI-Optionen (--url, --screenshot) → browser.init → register_callbacks → navigate → run
browser/browser.odin    Package browser: verbindet UI und HTTP-Client (Orchestrierung, Navigation)
browser/history.odin    History: besuchte URLs + Index (push, back, forward, replace_current)
http/client.odin        Package http: synchroner GET über libcurl easy-API
http/header.odin        header_value: Header aus der rohen Antwort lesen
http/url.odin           resolve_url (relative Links über curls URL-API), is_loadable_url
dom/                    Package dom: eigener DOM-Baum (Parsen über lexbor, dann umkopiert)
  dom.odin                Node, Document, destroy, attribute
  parse.odin              parse: lexbor-Baum → eigener Baum
  print.odin              tree_to_string (Debug/Tests)
  style.odin              Style, Color, ROOT_STYLE, default_style (Vererbung + UA-Stylesheet), apply_declaration
  css_values.odin         Wert-Parser: parse_color, parse_font_size, parse_font_weight
  box_style.odin          Box-Modell: Length/Edges, UA-Margins/Paddings (default_box), Kurzschreibweisen zerlegen
  border_style.odin       Rahmen: Border/Borders, border-Kurzschreibweisen (Teile in beliebiger Reihenfolge)
  media.odin              @media: Queries auswerten, passende Blöcke im CSS-Text auspacken (Mini-CSS-Scanner)
  custom_props.odin       CSS-Variablen: Deklarationen per lexbor-Walk sammeln, Custom Properties vererben, var() ersetzen
  plain_text.odin         from_plain_text: Text → Dokument html/body/pre (wie Chrome bei text/plain)
loader/loader.odin      Package loader: lädt + parst Seiten und lädt Ressourcen (Bilder) in einem Worker-Thread
layout/layout.odin      Package layout: DOM mit Styles → Hintergrund-Boxen + positionierte Text-Runs (Display List)
layout/table.odin       Tabellen-Layout (automatisch, vereinfacht): Gitter, min/max-content, Spaltenbreiten, Zeilen
layout/float.odin       Floats: Platzieren, Zeilen daneben kürzen, clear, eigene Block-Kontexte
ui/                     Package ui: raylib-Fenster, Komponenten, Rendering
  main_window.odin        MainWindow, init/destroy, Haupt-Loop (run)
  address_bar.odin        Adressleiste: Eingabe, Fokus, Enter → Callback
  nav_buttons.odin        Zurück/Vor/Neu laden bzw. Stopp: mit Formen gezeichnet, Klick + Tastenkürzel → Callback
  loading_bar.odin        animierter Ladebalken unter der Adressleiste
  page_images.odin        Bilder der Seite: dekodieren (raylib) → Texturen + natürliche Größen
  page_view.odin          Seitenansicht: besitzt Dokument + gecachtes Layout, zeichnet Text-Runs, Scrollen
  fonts.odin              globaler Font (fonts_init/fonts_close)
  constants.odin          UI-Konstanten (Höhen, Fontgröße, Scroll-Speed)
  screenshot.odin         Fenster als PNG speichern (Testmodus)
vendor/curl/            eigene Kopie der Odin-curl-Bindings (Package vendor_curl) + C-Header
vendor/curl-src/        git-Submodul: curl-Quellcode (nur für den Windows-Build)
vendor/lexbor-src/      git-Submodul: lexbor-Quellcode v3.0.1 (nur für den Windows-Build)
vendor/lexbor/          lexbor-Bindings + Tests (lexbor.odin: HTML/DOM, style.odin: CSS-Kaskade)
assets/fonts/           Inter 18pt Regular (Google Fonts) + Inter Bold (rsms/inter v4.1, extras/ttf), beide SIL OFL 1.1 (OFL.txt)
testdata/               lokale Fixtures für den Testmodus
setup.ps1               Windows-Setup (curl und lexbor bauen)
```

Import-Pfade sind relativ, z. B. `import "../ui"`, `import "../vendor/curl"`.

## Architektur

### Ablauf

1. `main` baut `ui.WindowSettings` (1024×768, „Browser“) und ruft `browser.init`; der `Browser` liegt auf dem **Heap** (`^Browser`), weil UI-Callbacks und der Worker-Thread Pointer darauf halten – eine zurückgegebene Struct-Kopie würde sie ungültig machen.
2. `browser.init`: zuerst `http.global_init` (vor jedem Thread), dann `ui.init` (raylib-Fenster, resizable, Escape schließt das Fenster **nicht** (`SetExitKey(.KEY_NULL)`), Fonts, AddressBar, PageView), dann `loader.init` (Worker-Thread mit eigenem curl-Handle). Bei Fehlern wird das bereits Erstellte wieder abgebaut. `destroy` beendet zuerst den Loader.
3. `browser.register_callbacks` setzt `on_url_submit`, `on_link_click`, `on_navigate` und `on_frame` (jeweils mit `_ctx` = Pointer auf den `Browser`) im `MainWindow`. Das ist der Mechanismus, mit dem die UI nach oben kommuniziert, ohne `browser`/`http` zu importieren.
4. `browser.run` → `ui.run`: klassischer raylib-Loop pro Frame:
   - `on_frame` → `browser.receive_pages` (holt fertige Seiten vom Loader, nie blockierend)
   - Resize → `address_bar_handle_resize`, `page_view_handle_resize`
   - `nav_buttons_handle_input` (Klick auf Zurück/Vor/Neu laden/Stopp, Alt+←/→, F5/Strg+R, Escape beim Laden → `on_navigate`)
   - `address_bar_handle_input` (Klick-Fokus nur aufs Eingabefeld, Zeichen, Backspace, Enter, Escape)
   - `page_view_handle_mouse` (Hand-Cursor über Links, Linksklick → `on_link_click`)
   - Mausrad → `page_view_handle_scroll`
   - `BeginDrawing` → `page_view_render`, dann `address_bar_render`, `nav_buttons_render` und beim Laden `loading_bar_render` (liegen oben drüber) → `EndDrawing`
   - `free_all(context.temp_allocator)` am Frame-Ende
5. Enter in der Adressleiste, Linkklick oder `--url` → `navigate` → `history_push` → `open_current`: Adressleiste und Button-Zustand setzen, `loader.load(url)` → `loading_id` merken, `ui.set_loading(true)`. **Es wird nicht gewartet**, das Fenster bleibt bedienbar.
   Pro Frame holt `receive_pages` Ergebnisse ab: Ergebnisse mit einer anderen ID als `loading_id` (veraltet) werden verworfen. Sonst `set_loading(false)`; bei Redirect `history_replace_current` + Adressleiste; Fehler → `page_view_set_content("Error: …")`, sonst `page_view_set_document` (Dokument wurde im Worker geparst). Beim Rendern baut die PageView bei Bedarf das Layout und zeichnet die Runs.
6. Klick auf einen Link → `on_link_click(href)` → `http.resolve_url(aktueller History-Eintrag, href)` → nur `http(s)` wird geladen (`navigate`), `mailto:` usw. werden ignoriert.
7. Zurück/Vor → `history_back`/`history_forward` + `open_current` (kein neuer Eintrag); Neu laden → `open_current`; Stopp → `loader.cancel`, `loading_id = 0`, `set_loading(false)`.

### Abhängigkeitsrichtung

`main` → `browser` → (`ui`, `http`, `dom`); `http` → `vendor/curl`; `ui` → `layout` → `dom` → `vendor/lexbor`; `browser` → `loader` → (`http`, `dom`). `ui` kennt weder `browser` noch `http`. Diese Richtung beibehalten; neue Kommunikation von UI nach oben über Callbacks mit `rawptr`-Context.

### Package-Details

**http** ([http/client.odin](http/client.odin))
- `Client` hält ein wiederverwendetes curl-Easy-Handle (curl macht Connection-Reuse intern) und je einen Builder für Header und Body.
- `header_value(raw, name)` sucht einen Header (case-insensitive); bei Redirects gewinnt der letzte Treffer.
- `resolve_url(base, ref)` nutzt curls URL-API (`curl_url_set` auf eine gesetzte URL löst relativ auf, RFC 3986). Die Binding von `url_get` war fehlerhaft (`-> ^Ucode`), korrigiert auf `-> Ucode` mit `part: ^cstring`; das Ergebnis mit `curl.free` freigeben.
- `global_init`/`global_cleanup`: einmal pro Programm, **bevor** Threads curl benutzen (`curl_global_init` ist nicht thread-sicher). `init` prüft `easy_init` auf `nil` und liefert `Maybe(Http_Error)`. Ein `Client` gehört immer genau einem Thread.
- `get(c, url, abort = nil)`: Mit `abort` (Pointer auf ein `bool`, atomar gesetzt von einem anderen Thread) bricht der Fortschritts-Callback (`XFERINFOFUNCTION`, mind. ~1×/s aufgerufen) den Transfer ab → Fehler `.E_ABORTED_BY_CALLBACK`.
- Jeder Request sendet `USER_AGENT` (`tobrod/0.1 (toy browser; +https://github.com/soerenlemke/tobrod)`); manche Seiten (z. B. Wikipedia) lehnen Requests ohne User-Agent ab.
- `get` folgt Redirects (`FOLLOWLOCATION`, max. `MAX_REDIRECTS` = 10); `Http_Response.url` ist die End-URL (`CURLINFO_EFFECTIVE_URL`, gehört curl, gültig bis zum nächsten `get`).
- `get` resettet beide Builder, setzt URL/Callbacks/Timeout (`STANDARD_READ_TIMEOUT` = 30 s) und führt `easy_perform` aus.
- `write_callback` ist `proc "c"` und setzt `context = runtime.default_context()`, bevor in den Builder geschrieben wird.
- Rückgabe `Http_Response{header, body}` – die Strings **zeigen in die Builder des Clients**, sind also nur bis zum nächsten `get` gültig.
- Fehler: `Maybe(Http_Error)` mit curl-Code und `easy_strerror`-Text.

**browser**
- `History` (`entries` gehören der History, `index` = aktueller Eintrag, -1 wenn leer). `history_push` verwirft die Vor-Einträge; `history_push`/`history_replace_current` klonen erst und geben dann frei, weil der übergebene String in die History zeigen kann. Der aktuelle Eintrag ist die Basis für relative Links (kein separates `current_url`).
- Bilder: Nach dem Anzeigen einer Seite sammelt `request_images` alle `<img src>` und `<video poster>` (jeden `src` einmal), löst sie gegen die Seiten-URL auf und übergibt sie dem Loader; `image_requests` merkt sich Request-ID → `src` (wie in der Seite, der Schlüssel fürs Layout). Fertige Bilder gehen an `ui.page_view_add_image`, Fehler werden still verworfen (Platzhalter bleibt). Eine neue Navigation oder Stopp vergisst die offenen Bild-Aufträge.
- Wie im Browser gilt eine Seite erst als geladen, wenn auch ihre Bilder da sind (`load`-Event): `update_loading_state` lässt Ladebalken/Stopp-Button an, solange Seite oder Bilder ausstehen. Dadurch wartet auch der Screenshot-Modus auf die Bilder.
- `navigate` klont die URL in den Temp-Allocator, weil sie in den Text der Adressleiste zeigen kann, den `open_current` überschreibt.

**ui**
- `MainWindow` besitzt `AddressBar`, `NavButtons`, `PageView`, `loading` und die Callbacks (Submit, Link, Navigation, Frame).
- Ladebalken (`loading_bar.odin`): unbestimmter Fortschritt, ein Segment (30 % Breite) läuft in 1,2 s von links nach rechts, berechnet aus `rl.GetTime()`. Funktioniert nur, weil die Hauptschleife während des Ladens weiterläuft. `page_view_handle_mouse` kopiert den Link vor dem Callback in den Temp-Allocator, weil das Laden der neuen Seite das Layout (und damit den String) zerstört.
- `AddressBar`: Text in einem `strings.Builder`; Eingabefeld (`address_bar_input_rect`) beginnt rechts der Navigations-Buttons und reicht bis 8 px vor den rechten Rand. Nur ein Klick ins Eingabefeld fokussiert.
- `NavButtons`: `can_back`/`can_forward` (gesetzt vom Browser über `set_navigation_state`), `loading` (über `set_loading`: dann zeigt der dritte Button Stopp ✕ statt Reload, `Nav_Action.Stop` teilt sich den Platz mit `.Reload`), Buttons à 24 px; Icons mit `DrawLineEx`/`DrawRing`/`DrawTriangle` gezeichnet (Inter hat kein ↻). raylib lässt Dreiecke mit Ecken im Uhrzeigersinn weg (Backface Culling) → `draw_triangle_any_order`. Deaktivierte Buttons grau, Hover hellgrau hinterlegt. Fokusfarbe Blau `{66,133,244}`.
- `PageView` zeichnet in der Reihenfolge der Display List: Seitenhintergrund (`page_layout.background`), Boxen (Hintergrund, dann die vier Rahmen als Rechtecke), Bilder (Textur skaliert auf die Layout-Größe per `DrawTexturePro`, sonst grauer Platzhalter `draw_image_placeholder`), Text (jeweils nur Sichtbares).
- Bilder (`page_images.odin`): `page_view_add_image` dekodiert mit `rl.LoadImageFromMemory` (Format über Content-Type bzw. URL-Endung, `image_file_type`: PNG, JPG, GIF (erstes Bild), BMP, QOI; kein SVG/WebP) auf dem UI-Thread, weil Texturen nur dort erzeugt werden dürfen, lädt sie als Textur (bilinearer Filter), trägt die natürliche Größe in `image_sizes` ein und verwirft das Layout, damit es mit der echten Größe neu gebaut wird. `images`/`image_sizes` hängen am Dokument und werden mit ihm freigegeben (Schlüssel geteilt). Das Layout wird neu gebaut, wenn sich Breite **oder** Höhe ändert (wegen `vh`). `rect` unterhalb der Adressleiste, `document` (gehört der PageView: `page_view_set_document` übernimmt es, `page_view_set_content` verpackt Text per `dom.from_plain_text`), `page_layout` (gecacht, `page_view_ensure_layout` baut nur neu, wenn sich die Breite ändert), `scroll_y`, `content_height` (= Layout-Höhe). `page_view_render` zeichnet nur Runs im sichtbaren Bereich (Scissor-Mode). `measure_text` ist die `Measure_Text`-Proc für das Layout (raylib). Fette Runs werden mit `font_bold` gezeichnet und gemessen (`font_for(bold)`). Scrollen wird auf `[0, content_height - rect.height]` begrenzt (`clamp_scroll`).
- `font` und `font_bold` sind Package-globale Variablen (`fonts_init` lädt beide, Pfade in `FONT_REGULAR_PATH`/`FONT_BOLD_PATH`), jeweils einmal mit `FONT_LOAD_SIZE` (64) gerastert und beim Zeichnen auf die jeweilige Größe skaliert; Mipmaps + trilinearer Filter halten kleinen Text glatt. Geladen werden die Codepoints aus `font_codepoints` (ASCII, Latin-1, typografische Zeichen).

**dom** ([dom/](dom/))
- `parse(html, stylesheets = {}, media = DEFAULT_MEDIA) -> (^Document, Maybe(Parse_Error))`: parst mit lexbor, kopiert rekursiv in eigene `Node`s und zerstört das lexbor-Dokument sofort. Danach zeigt nichts mehr in lexbors Speicher.
- `Node`: `kind` (`Document`/`Element`/`Text`/`Comment`), `parent`, `children` (`[dynamic]^Node`), `tag` (lowercase), `attributes` (`[]Attribute`, Quellreihenfolge), `text`, `style` (nur Elemente). Doctype und Processing Instructions werden weggelassen.
- Speicher: Ein `virtual.Arena` pro `Document`, alle Nodes und Strings liegen darin; `destroy` gibt alles auf einmal frei.
- lexbor ergänzt fehlendes `<html>`/`<head>`/`<body>` wie ein echter Browser.
- Externe Stylesheets: Mit einem `Stylesheet_Loader` (Callback `load(ctx, href) -> (css, ok)` + `ctx`; `href` zeigt in lexbors Speicher und gilt nur während des Aufrufs – wer ihn behalten will, muss ihn kopieren. Das hat in einem Test einen sporadischen Use-after-free-Absturz verursacht.) sucht `parse` nach dem HTML-Parsen alle `<link rel="stylesheet">` (ohne `alternate`, ohne `media="print"`), holt den CSS-Text über den Callback, parst ihn mit lexbors CSS-Parser (`lxb_css_stylesheet_parse`) und hängt ihn an (`lxb_html_document_stylesheet_attach_noi`), **bevor** die Styles gelesen werden. Wie im Browser blockieren sie die Seite („render-blocking“), damit sie nie erst ungestylt erscheint. Der Callback hält `dom` frei von HTTP; fehlende Stylesheets werden übersprungen. Stylesheets und Parser werden vor dem lexbor-Dokument zerstört (wie in lexbors Beispiel).
- Styles (`Style`: `display`, `color` (eigener Typ `Color :: [4]u8`, kein raylib), `font_size` in px, `font_weight` 1..1000): `parse` ruft `lxb_style_init` vor dem Parsen auf; der Document-Node hat `ROOT_STYLE` (schwarz, 16 px, 400). Pro Element in drei Schritten wie im Browser:
  1. vererbte Properties (`color`, `font-size`, `font-weight`) vom Eltern-Node, `display` nicht,
  2. `default_style(tag, hidden, parent)`: unser vereinfachtes UA-Stylesheet (Block-Tags, `li` = `List_Item`, `head`/`script`/… und `hidden` = `None`, `h1`–`h6` Größe + fett, `b`/`strong` fett, `small` kleiner, `a` = `LINK_COLOR`),
  3. `apply_declaration` für jede Property aus `STYLE_PROPERTIES`, die lexbors Kaskade liefert. Unbekannte Werte werden ignoriert (Default bleibt). `inherit`/`initial`/`unset` werden behandelt.
- Box-Modell (`box_style.odin`, nicht vererbt): `margin`/`padding` als `Edges` (`[Edge]Length`, Index `.Top/.Right/.Bottom/.Left`), `width`, `height` (bisher nur für Bilder genutzt), `max_width` (`.Auto` = keins), `background` (Alpha 0 = transparent). `Length` hat die Einheiten `Px`, `Em` (gegen die eigene, finale Schriftgröße), `Percent` (gegen die Breite des umgebenden Blocks, auch vertikal) und `Auto`; aufgelöst wird erst im Layout (`resolve_length`). `rem`/`pt` werden sofort in px umgerechnet. Die UA-Margins/Paddings (`body` 8px, `p` 1em 0, `ul`/`ol` padding-left 40px, Überschriften, `blockquote`, …) stehen in `default_box`.
- **lexbor löst Kurzschreibweisen nicht auf** (`margin: 0 auto` kommt nur als `margin`, `margin-top` bleibt leer; ebenso `padding`, `border`, `background`). Wir zerlegen `margin`/`padding` (1–4 Werte) selbst und holen die Farbe aus `background` (`background_color_of`, trennt an Leerzeichen außerhalb von Klammern). Reihenfolge in `STYLE_PROPERTIES`: Kurzform vor Langform, die Langform gewinnt. **Einschränkung:** Wir kennen nur die Werte, nicht ihre Spezifität – `.a.b { margin: 0 }` gegen `.a { margin-top: 5px }` ergibt fälschlich 5px.
- `light-dark(a, b)` liefert die helle Farbe `a` (wir haben nur ein helles Theme). `vw`/`vh` werden gegen den Viewport (sichtbarer Seitenbereich) aufgelöst. Unbekannte Einheiten (`ch`, `ex`, …) machen die ganze Deklaration ungültig, sie wird ignoriert.
- `text_align` (`Left`/`Center`/`Right`, `justify` = links) wird **vererbt**; UA: `center` und `th` zentriert.
- `float` (`None`/`Left`/`Right`) und `clear` (`None`/`Left`/`Right`/`Both`), nicht vererbt; schwebende Inline-Elemente werden zu Blöcken („Blockification“ am Ende von `compute_style`).
- Tabellen: `display` hat `Table`, `Table_Row_Group` (thead/tbody/tfoot), `Table_Row`, `Table_Cell`, `Table_Caption` (UA: table/tr/td/th/caption; `col`/`colgroup` = None). `vertical_align` (`Top`/`Middle`/`Bottom`, `baseline` = top; UA: `td`/`th` = Middle), `border_collapse` und `caption_bottom` (`caption-side`) werden vererbt; UA: `td`/`th` padding 1px.
- `visibility` (`Visible`/`Hidden`, `collapse` = hidden) wird vererbt, ein Kind kann wieder `visible` sein. `list_style` (`Disc`/`Circle`/`Square`/`Decimal`/`None`; alphabetisch/römisch → Decimal) wird vererbt, UA: `ol` = Decimal; `list-style`-Kurzform: nur der Typ wird gelesen. `position` (`Static`/`Relative`/`Absolute`/`Fixed`/`Sticky`) wird nicht vererbt.
- Rahmen (`border_style.odin`): pro Seite `Border{width: Length, style: Border_Style, color: Maybe(Color)}` (`nil` = `currentcolor`). Initial: `medium` (3px), Stil `None` (also unsichtbar). Alle sichtbaren Stile (`dashed`, `dotted`, …) werden als durchgezogene Linie gezeichnet. `border`/`border-top`… zerlegen wir selbst, die Teile dürfen in beliebiger Reihenfolge stehen und werden nach Art erkannt (Stil-Schlüsselwort, Breite, Farbe); fehlende Teile werden auf den Initialwert gesetzt. `border-width/-style/-color` mit 1–4 Werten (`expand_four`), Langformen wie `border-left-color`. `split_outside_parens` trennt an Leerzeichen außerhalb von Klammern. UA: `hr` hat einen 1px grauen Rahmen.
- lexbor serialisiert normalisiert (lowercase, `#F00` → `#f00`, Kommas vereinheitlicht), lässt relative Einheiten (`em`, `%`, `smaller`, `bolder`) aber stehen – die rechnen wir gegen den Eltern-Style um. Unterstützt: Farben benannt (Teilmenge), Hex, `rgb()`/`rgba()`, `transparent`, `currentcolor` (kein `hsl()`); Größen `px`, `em`, `rem`, `%`, `pt`, Schlüsselwörter; Gewichte `normal`/`bold`/Zahl/`bolder`/`lighter`. Nicht unterstützte Layout-Modi fallen bei `display` auf ihr äußeres Verhalten zurück.

**loader** ([loader/loader.odin](loader/loader.odin))
- Wird vom `browser` benutzt (Feld `page_loader`: ein Feld namens `loader` würde den Package-Namen verdecken → „declaration cycle“).
- Ein Worker-Thread mit **eigenem** `http.Client` (ein curl-Handle darf nie von zwei Threads gleichzeitig benutzt werden). `load(url) -> Request_Id` übergibt einen Auftrag, `poll() -> (Result, ok)` holt fertige Ergebnisse ab (nie blockierend, gedacht für einmal pro Frame), `cancel()` bricht ab, `destroy` beendet den Worker (bricht einen laufenden Download ab, hängt also nicht).
- Zwei Arten von Aufträgen (`Request_Kind`): `.Page` (`load`, wird geparst) und `.Resource` (`load_resource`, liefert rohe Bytes in `Result.data` + `content_type`). Seiten haben Vorrang. Es gibt höchstens **eine** wartende Seite: `load` ersetzt sie, **verwirft alle wartenden Ressourcen** (sie gehörten zur alten Seite) und bricht den laufenden Auftrag ab. Ressourcen warten in einer Queue (`resources`) und werden nacheinander geladen. `cancel` verwirft alles. Abgebrochene Aufträge liefern kein Ergebnis. Über die `Request_Id` erkennt der Aufrufer veraltete Ergebnisse.
- `load(url, media)`: `media` ist die Größe der Seitenansicht, die der Browser beim Start der Navigation mitgibt; der Worker reicht sie an `dom.parse` weiter.
- Externe Stylesheets lädt der Worker während `dom.parse` über den Callback `load_stylesheet` mit demselben `http.Client` (relativ zur Seiten-URL). Das überschreibt die Antwort-Puffer der Seite, deshalb wird `response` danach nicht mehr benutzt. Wird währenddessen abgebrochen, wird die halbfertige Seite verworfen.
- Der Worker parst auch (`dom.parse` bzw. `dom.from_plain_text`), `Result` enthält ein fertiges Dokument oder einen Fehlertext und gehört dem Empfänger (`result_destroy`).
- Synchronisation: `pending`, `results`, `quit` nur unter `mutex`; der Worker schläft auf `cond` (Condition Variable). `abort` wird ohne Mutex vom curl-Fortschritts-Callback gelesen, daher nur atomar (`sync.atomic_load/store`); zurückgesetzt wird es unter dem Mutex, wenn der Worker einen Auftrag übernimmt.
- Speicher: Alles, was zwischen Threads wandert, nutzt den beim `init` übergebenen Allocator (der Worker setzt ihn als `context.allocator`, hat aber seinen eigenen Temp-Allocator und leert ihn nach jedem Auftrag). Odins Tracking-Allocator (Tests) hat einen Mutex, ist also thread-sicher.
- Tests starten einen eigenen HTTP-Server auf einem freien Port (`core:net`, ein Thread pro Verbindung) mit `/page.html`, `/text`, `/redirect`, `/slow` (5 s). `@(init)`-Procs müssen `"contextless"` sein; dort wird `curl_global_init` direkt aufgerufen.

**layout** ([layout/layout.odin](layout/layout.odin))
- `build(doc, width, measure) -> ^Layout` liefert `background` (Seitenhintergrund), `boxes: [dynamic]Box` (Hintergründe von Block-Boxen, Eltern vor Kindern) und `runs: [dynamic]Text_Run` (`text`, `x`, `y` = linke obere Ecke, `width`, `font_size`, `bold`, `color`, `link` = `href` des umgebenden `<a>`, roh wie in der Seite) und `height`; `link_at(l, x, y)` findet den Link unter einem Punkt (ganze Zeilenbox zählt). Runs werden an Link-Grenzen getrennt. `destroy` gibt alles frei (eine Arena pro Layout).
- Kennt keine Fonts: Textbreite kommt über `Measure_Text`; die UI übergibt raylib, die Tests `fake_measure` (Zeichen × Größe × 0,5) für exakte Erwartungen.
- `build(doc, viewport, measure, image_sizes = nil)`: `viewport` = Breite und Höhe der Seitenansicht (Breite = Seitenbreite, beides für `vw`/`vh`); `image_sizes` = natürliche Größen bereits geladener Bilder, Schlüssel ist `src` wie in der Seite.
- **Ersetzte Elemente** (`is_replaced_element`: `img`, `video`, `iframe`, `canvas`, `embed`, `object`) laufen alle durch `layout_image`: ein Rechteck fester Größe, dessen Inhalt von außen kommt. Bild-Quelle (`image_source`): `src` bei `img`, das Vorschaubild `poster` bei `video` (abspielen können wir nicht), sonst keine (Platzhalter). Unbekannte Größe: 16 px bei `img`, sonst der Browser-Standard **300 × 150** (`REPLACED_DEFAULT_SIZE`). Ihre Kinder (z. B. `<source>`) werden nicht gelayoutet. Wikipedia bettet Videos als `<video poster>` ein – ohne das war die Abbildung 0 px breit.
- Bilder (`layout_image`): Inline-Element mit fester Größe, in der Zeile wie ein großes Wort (Umbruch, Leerzeichen davor, `text-align`); die Zeile wird so hoch wie das höchste Element, alles sitzt unten. Größe (`image_size`): 1. CSS `width`/`height`, 2. Attribute `width`/`height`, 3. natürliche Größe aus `image_sizes`; ist nur eine Seite bekannt, folgt die andere dem Seitenverhältnis; Unbekanntes = `IMAGE_PLACEHOLDER_SIZE` (16). `max-width` verkleinert proportional. Ergebnis: `images: [dynamic]Image_Item` (`src`, Position, Größe, `link`). `link_at` prüft auch Bilder. `line_empty` berücksichtigt Text und Bilder der Zeile.
- Block-Layout (`layout_block`) nach dem CSS-Box-Modell, vereinfacht (kein `height`, immer `content-box`). Padding und Rahmen verhalten sich für Breite und Margin-Collapsing gleich (`inset` = Padding + Rahmen):
  - Horizontal: verfügbare Breite − Margins − Paddings = Inhaltsbreite, begrenzt durch `width`/`max-width`; übriger Platz geht an `auto`-Margins (beide `auto` = zentriert).
  - Vertikal: Margins kollabieren lazy (`pending_margin` = max). Padding oder Rahmen stoppen das Collapsing (`flush_margin` vor dem Padding). Die Oberkante eines Blocks ist erst bekannt, wenn der kollabierte Margin angewendet wird: offene Blöcke liegen auf `block_tops` und werden in `flush_margin` aufgelöst (alle noch offenen bekommen dieselbe Oberkante). Leere Blöcke ohne Padding haben Höhe 0.
  - Boxen (Hintergrund und/oder Rahmen): Slot in `boxes` beim Betreten reservieren (Zeichenreihenfolge Eltern → Kinder), Maße beim Verlassen eintragen. `Box` hat `border` (Breiten in px) und `border_color` pro Seite. Der Hintergrund von `html`/`body` färbt stattdessen die ganze Seite (`background`, „Canvas“; `html` hat Vorrang), ihre Rahmen bleiben an der Box.
  - `position: absolute`/`fixed`: Elemente werden übersprungen (aus dem Fluss genommen, aber noch nicht platziert); `relative`/`sticky` wie `static`.
  - `visibility: hidden`: Text-Runs, Bilder und Boxen nehmen ihren Platz ein, werden aber nicht in die Display List übernommen (`hidden`-Flag, ausgefiltert in `finish_line` bzw. beim Box-Slot).
  - Listen-Marker: Typ aus `list_style` (`•`, `◦`, `▪`, `1.`; keiner bei `None`). Der Marker gehört an die **erste Zeile** des `li`, auch wenn die tief in verschachtelten Blöcken liegt: `set_pending_marker` merkt ihn vor (mit der Inhaltskante des `li`), `start_line` setzt ihn. Leere `li` bekommen keinen. Die Glyphen ◦ und ▪ sind in `font_codepoints` ergänzt.
  - Tabellen (`table.odin`, `layout_table`): 1. Gitter aus Zeilen (direkt oder in thead/tbody/tfoot) und Zellen, `colspan` (kein `rowspan`); Inhalt ohne Zeile/Zelle wird wie im Standard in eine **anonyme Zeile/Zelle** verpackt (`anonymous_box`, ein Layout-Node, der die Kinder hält, ohne ihr Parent zu werden) – Wikipedia baut Bilder so (`<figure style="display: table">`). 2. Jede Zelle wird per **Probe-Layout** (`measure_contents`: eigener Builder mit Wegwerf-Arena, `measuring = true` schaltet `text-align` ab) zweimal gemessen: Breite 0 (min-content) und `MAX_CONTENT_WIDTH` (max-content); Ergebnis ist `extent` (rechteste Kante von Text/Bildern). 3. Spaltenbreiten: passt max-content, bekommt jede Spalte ihr Maximum (Extraplatz bei expliziter Tabellenbreite proportional), sonst min + Anteil am Rest proportional zu (max − min); `colspan`-Zellen verbreitern ihre Spalten gleichmäßig. 4. Zeilen: Zellinhalt per `layout_cell_contents` (eigener Block-Kontext, Margins kollabieren nicht heraus), Zeilenhöhe = höchste Zelle, dann `vertical-align` (nur der Bereich der jeweiligen Zelle in der Display List wird verschoben), Zellen-/Zeilen-/Tabellen-Boxen per `reserve_box`/`fill_box`. Abstand zwischen Zellen 2px (`border-spacing` wird nicht gelesen), 0 bei `border-collapse` (Rahmen werden dann nicht zusammengelegt, nur aneinandergesetzt). Captions oben bzw. unten (`caption-side: bottom`).
  - Floats (`float.odin`): Der Builder führt `floats` (Margin-Boxen) des aktuellen Block-Formatierungskontexts. `layout_float`: Breite = `width` oder **shrink-to-fit** (`min(max(min-content, verfügbar), max-content)`, gemessen per Probe-Layout des Knotens selbst, `measure_node`; Tabellen messen sich über ihre Box, `fill_box` erweitert `extent`), y = wo die nächste Zeile beginnen würde (nicht über früheren Floats), x am linken/rechten Rand bzw. darunter, wenn er nicht neben andere passt; Inhalt per `layout_in_own_context` (eigener Kontext, `unfloat` verhindert erneutes Floaten, Zustand inkl. halbfertiger Zeile wird gesichert). Zeilen: `start_line(b, höhe)` setzt `line_left`/`line_right` aus `line_bounds` (Floats auf dieser Höhe); passt ein Wort/Bild nicht daneben, rutscht die Zeile unter den nächsten endenden Float (`fit_line`). Block-Boxen laufen hinter Floats durch, nur ihre Zeilen werden kürzer. `clear` auf Blöcken setzt sie unter die Floats der Seite(n). Tabellenzellen und Floats sind eigene Kontexte: innere Floats wirken nicht nach außen, machen sie aber höher. Die Seitenhöhe berücksichtigt Floats.
  - `text-align`: `b.text_align` gilt für die Zeilen des aktuellen Blocks; `finish_line` verschiebt alle Runs einer Zeile um den freien Platz zwischen `line_left`/`line_right` (bzw. die Hälfte). Listen-Marker (links von `b.left`) bleiben stehen.
  - Seitenrand und Listeneinzug sind keine Spezialfälle mehr, sondern UA-Styles (`body`-Margin, `ul`-Padding). Listen-Marker hängen links in das Padding.
- Inline-Layout: Text wird an Wörtern umgebrochen, gleich gestylte Wörter einer Zeile werden zu einem Run zusammengefasst (`can_extend`). Zeilenhöhe = größte Schrift × 1,25, kleinere Schrift sitzt unten. Inline-Elemente haben noch keine Hintergründe.
- `<br>` beendet die Zeile (auf leerer Zeile: Leerzeile). In `<pre>` bleiben Leerzeichen/Umbrüche erhalten, lange Zeilen brechen trotzdem um (wie `pre-wrap`); Tabs = 4 Leerzeichen. Fett ab `font_weight >= 600`.

**vendor/lexbor** ([vendor/lexbor/lexbor.odin](vendor/lexbor/lexbor.odin))
- Opake Typen `Html_Document` und `Dom_Node`, `Status`/`STATUS_OK`, `Dom_Node_Type`; Funktionen `lxb_html_document_create/parse/destroy`, `lxb_html_document_body_element_noi` und die Traversal-Procs `lxb_dom_node_{first_child,last_child,next,prev,parent,type}_noi`. `document_node` castet ein Dokument zum Node (wie lexbors `lxb_dom_interface_node`). Genutzt werden die `_noi`-Varianten, weil die normalen Funktionen `static inline` sind.
- Node-Daten: opake `Dom_Element`/`Dom_Attr`; `element_from_node` castet nur Element-Nodes (sonst `nil`). Helper `element_name`, `element_attribute` (über `lxb_dom_element_attr_by_name`, weil `get_attribute` „fehlt“ und „ohne Wert“ nicht unterscheidet), `attr_name`/`attr_value`, `node_text_content`.
- Speicher: Namen und Attributwerte zeigen in lexbors Speicher und gelten, solange das Dokument lebt. `node_text_content` liefert dagegen eine Kopie (Caller gibt frei), weil lexbor den Text separat allokiert und wir ihn sofort mit `lxb_dom_document_destroy_text_noi` freigeben.
- Noch nicht in `main`/`browser` eingebunden.
- `@media` (`media.odin`): Weil lexbor `@media`-Blöcke überspringt, bereiten wir den CSS-Text vorher auf: `apply_media_queries(css, env)` packt passende Blöcke aus (Regeln bleiben, Hülle fällt weg) und entfernt unpassende; verschachtelte werden mit ausgewertet. Ein kleiner Scanner zählt Klammern und überspringt Kommentare und Strings. Ausgewertet wird gegen `Media_Env{width, height}` (Größe der Seitenansicht **beim Laden**; Größenänderungen danach wirken erst nach Neu laden): Medientypen `all`/`screen` (nicht `print`), `not`/`only`, Listen mit `,`, `and`; Features `min-/max-width/height`, `width`/`height`, Range-Syntax (`width >= 640px`), Längen in px/em/rem und einfachem `calc(a ± b)`, `orientation`, `prefers-color-scheme` (nur `light`), `hover`/`pointer` (Maus), `prefers-reduced-motion: no-preference`; Unbekanntes passt nie. Externe Stylesheets werden komplett aufbereitet; bei `<style>`-Elementen (die lexbor schon ohne ihre `@media`-Blöcke angewendet hat) wird nur der Inhalt passender Blöcke zusätzlich angehängt (`only_media`).
- Verhalten von lexbor (per Probe ermittelt): angehängte Stylesheets greifen in der Kaskade; **`@media`-Blöcke werden komplett übersprungen**, auch passende. Custom Properties (`--x`) kennt lexbor (Typ 1, Rohwert). Deklarationen mit `var()` landen als „undef“ (Typ 0) mit Rohtext, **verlieren aber in lexbors Kaskade** gegen eine normale Deklaration derselben Property, auch wenn sie später kommen – `lxb_dom_element_style_by_name` liefert dann die falsche.
- Werte, die lexbor nicht parsen kann („undef“, Typ 0), z. B. **`clear: both`** (lexbor kennt nur `left`/`right`), bekommen eine Chance bei unseren Parsern: `compute_style` wendet erst lexbors typisierten Wert an und darüber den Rohwert, wenn dessen Spezifität ≥ ist. Ist der Rohwert auch für uns ungültig, ignoriert ihn `apply_declaration` und der typisierte Wert bleibt (wie Browser ungültige Deklarationen verwerfen).
- CSS-Variablen (`custom_props.odin`): `compute_style` geht per `lxb_dom_element_style_walk` alle Deklarationen eines Elements durch (Name, Rohwert, Spezifität, `is_weak`) und sammelt Custom Properties, `var()`-Deklarationen und die höchste Spezifität der normalen Deklarationen je Property. Custom Properties werden vererbt (`Custom_Props`-Map im Temp-Allocator; Elemente ohne eigene teilen die Map der Eltern), ihre Werte werden beim Element mit ersetztem `var()` gespeichert. Eine `var()`-Deklaration gewinnt, wenn ihre Spezifität **≥** der normalen ist (Gleichstand: typisch `color: #000; color: var(--x)`). `substitute_vars` ersetzt `var(--n)`/`var(--n, fallback)` (verschachtelt, Groß-/Kleinschreibung egal, Zyklus-Schutz über Tiefe 16); fehlt eine Variable ohne Fallback, wird die Property `unset` (wie im Standard, nicht die unterlegene Deklaration). Das Ergebnis wird kleingeschrieben und läuft durch die normalen Wert-Parser.
- CSS ([vendor/lexbor/style.odin](vendor/lexbor/style.odin)): `lxb_style_init` vor dem Parsen, `lxb_style_destroy` vor `lxb_html_document_destroy`. Danach liest lexbor `<style>` und `style=""` selbst ein und macht die Kaskade (Selektoren, Spezifität, `!important`, Reihenfolge). `element_style(el, "color")` liefert den gewinnenden Wert als String (kopiert, Caller gibt frei) – nur Deklariertes, keine geerbten oder Default-Werte.
- `Css_Rule_Declaration` bildet den **Anfang** von `lxb_css_rule_declaration_t` nach (`rule`, `type`, Wert-Pointer), damit `lxb_css_property_serialize` aufgerufen werden kann. Beim Update des Submoduls `css/rule.h` prüfen.
- `foreign import lib` ist mit `@(export)` markiert, weil Foreign Imports sonst nur in ihrer Datei sichtbar sind.
- Der eigene DOM-Baum ist im Package `dom`; `vendor/lexbor` wird nur von dort benutzt.

## Code-Konventionen

- Einrückung mit Tabs (Odin-Standard), Struct-Felder ausgerichtet.
- Packages = Ordner, ein Konzept pro Datei.
- Procs in `snake_case`, innerhalb eines Packages mit Komponenten-Präfix: `address_bar_init`, `page_view_render`, `fonts_close`. Package-Lebenszyklus-Procs heißen schlicht `init` / `destroy` / `run` (Aufruf dann `ui.init`, `http.get`).
- Typen: bisher gemischt (`MainWindow`, `AddressBar`, `PageView` vs. `Http_Error`, `Http_Response`, `Html_Document`). Für neuen Code `Ada_Case` (Odin-Konvention) bevorzugen bzw. sich am jeweiligen Package orientieren.
- Konstanten in `SCREAMING_SNAKE_CASE`, UI-weite Werte in [ui/constants.odin](ui/constants.odin).
- Fehlerbehandlung: Fehler als zweiter Rückgabewert `Maybe(XxxError)`, Prüfung mit `if err, ok := err.?; ok { … }`. Kein Panic für erwartbare Fehler. Bei Teil-Initialisierung bereits erstellte Ressourcen wieder freigeben.
- Speicher: Frame-lokale Allokationen (cstrings fürs Zeichnen, Textumbruch) über `context.temp_allocator`; der wird am Ende jedes Frames in `ui.run` geleert. Langlebiges explizit mit `defer delete(...)` bzw. in `destroy` freigeben.
- C-Interop: `strings.clone_to_cstring` für Strings an C; C-Callbacks als `proc "c"` mit gesetztem Context. Auf Windows sind curl und lexbor mit `/MD` gebaut, ihre Foreign Imports setzen deshalb `/NODEFAULTLIB:libcmt` (sonst scheitern eigenständige Builds wie `odin test http`).
- `defer` gilt in Odin pro **Block**, nicht pro Proc: ein `defer` im `if` läuft am Ende des `if`.
- Kommentare kurz und auf Englisch, erklären das *Warum*.

## Bekannte Probleme und offene Punkte

Beim Durchsehen aufgefallen (Stand 2026-10-17), noch nicht behoben:

1. ~~Dangling-String bei HTTP-Fehlern~~ / ~~Body-Lebensdauer~~ – behoben: `PageView` besitzt sein Dokument (`page_view_set_document`/`page_view_set_content`), freigegeben in `page_view_destroy` bzw. beim nächsten Setzen.
2. *(in 1 zusammengefasst)*
3. ~~Backspace entfernt ein Byte statt einer Rune~~ – behoben mit `strings.pop_rune`.
4. ~~HTTP blockiert den UI-Thread~~ – behoben (Stage 5): Laden und Parsen laufen im Worker-Thread (`loader`).
5. ~~`http.init` prüft nicht auf `nil`, kein `curl_global_init`~~ – behoben: `http.init` prüft, `browser.init` ruft `http.global_init` vor dem Start des Worker-Threads.
6. ~~`ui.destroy` gibt den `strings.Builder` der Adressleiste nicht frei~~ – behoben.
7. `address_bar_render` allokiert pro Frame eine cstring auf dem Heap (könnte Temp-Allocator nutzen).
8. ~~Fokus-Klick prüft die ganze Adressleiste statt nur das Eingabefeld~~ – behoben (`address_bar_input_rect`).
9. ~~Textumbruch läuft jeden Frame neu~~ – behoben: Das Layout wird gecacht und nur bei Breiten- oder Inhaltsänderung neu gebaut.
10. ~~lexbor auf Windows~~ – behoben: wird von `setup.ps1` aus dem Submodul `vendor/lexbor-src` statisch gebaut. Weil Odin standardmäßig die statische CRT (`libcmt`) linkt, setzt das Binding wie `vendor:raylib` `/NODEFAULTLIB:libcmt` (sonst scheitert `odin test vendor/lexbor` an `__imp__dsign`).
11. URL-Eingabe ohne Schema (`example.com`) wird nicht automatisch zu `http(s)://` ergänzt (steht als TODO in der Roadmap).
12. Linux ist bisher weder dokumentiert noch getestet.
13. ~~Nicht-ASCII-Zeichen werden als `?` gezeichnet~~ – behoben: `fonts_init` lädt ASCII, Latin-1 und ein paar typografische Zeichen (`– „“ … €`). Andere Schriften (z. B. Kyrillisch, CJK) erscheinen weiterhin als `?`; dafür bräuchte es Glyphen bei Bedarf.
14. ~~Zeilenumbrüche im Inhalt gehen verloren~~ – behoben: Plain Text läuft als `<pre>` durchs Layout, Umbrüche bleiben erhalten.

## Roadmap (Kurzfassung, Details im README)

- Stage 1 HTTP-Client – erledigt
- Stage 2 Fenster & UI – Fenster, Adressleiste, klickbare Links und Navigation (zurück/vor/neu laden) stehen; offen: Schema-Ergänzung, Tabs
- Stage 3 Rohtext-Rendering – erledigt (Text, Umbruch, Scrollen)
- Stage 4 HTML & CSS – lexbor-Bindings und eigener DOM-Baum (`dom`) fertig, CSS-Kaskade über lexbor gebunden; `display`, `color`, `font-size`, `font-weight` werden berechnet (Vererbung + Defaults + CSS); Package `layout` erzeugt positionierte Text-Runs, die UI zeichnet sie mit Größe, Fett (Inter Bold) und Farbe. Links sind klickbar (relative URLs über curl). Box-Modell (margin, padding, width, max-width, auto-Zentrierung, Hintergründe, Rahmen), `text-align`, `vw`/`vh`, Bilder (PNG/JPG/GIF/BMP/QOI, laden im Hintergrund, Platzhalter). Externe Stylesheets, `@media`, `visibility`, `position: absolute/fixed` (übersprungen), `list-style`. CSS-Variablen (`var()`), Tabellen (ohne `rowspan`), Floats. Offen: Flexbox & Co., `height` für Blöcke, SVG/WebP, Inline-Hintergründe, echte Positionierung, `calc()` in Längen.
- Stage 5 Threads – erledigt: Laden + Parsen im Worker-Thread (`loader`), Ergebnisse per Queue, eigener curl-Handle pro Thread, Abbrechen; Ladebalken + Stopp-Button
- Stage 6 JavaScript – QuickJS anbinden
