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
odin test layout           # Layout (mit Fake-Textmessung, ohne Fenster)
```

**Immer aus dem Repo-Root starten**: Die Fonts werden über relative Pfade (`assets/fonts/Inter_18pt-Regular.ttf`, `assets/fonts/Inter-Bold.ttf`) geladen ([ui/fonts.odin](ui/fonts.odin)).

Stand 2026-10-17 auf macOS und Windows (Odin `dev-2026-05`, nach `setup.ps1`): `odin check .`, `odin build .` und `odin test vendor/lexbor` laufen erfolgreich durch.

### Visuelle Tests (Testmodus)

`tobrod` hat zwei Kommandozeilen-Optionen (geparst mit `core:flags`, Unix-Stil):

- `--url <url>` lädt die URL direkt beim Start (wie Eingabe in der Adressleiste + Enter).
- `--screenshot <pfad>` rendert ein paar Frames (`SCREENSHOT_AFTER_FRAMES`), speichert das Fenster als PNG und beendet sich. Exit-Code 1, wenn das Bild nicht geschrieben werden kann.

Lokale Fixtures liegen in [testdata/](testdata/) (`hello.txt`, `utf8.txt`, `long.txt`, `index.html`, `styles.html` – Überschriften, Fett, Farben, Größen, Listen, `pre`, `br`):

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
browser/browser.odin    Package browser: verbindet UI und HTTP-Client (Orchestrierung)
http/client.odin        Package http: synchroner GET über libcurl easy-API
http/header.odin        header_value: Header aus der rohen Antwort lesen
http/url.odin           resolve_url (relative Links über curls URL-API), is_loadable_url
dom/                    Package dom: eigener DOM-Baum (Parsen über lexbor, dann umkopiert)
  dom.odin                Node, Document, destroy, attribute
  parse.odin              parse: lexbor-Baum → eigener Baum
  print.odin              tree_to_string (Debug/Tests)
  style.odin              Style, Color, ROOT_STYLE, default_style (Vererbung + UA-Stylesheet), apply_declaration
  css_values.odin         Wert-Parser: parse_color, parse_font_size, parse_font_weight
  plain_text.odin         from_plain_text: Text → Dokument html/body/pre (wie Chrome bei text/plain)
layout/layout.odin      Package layout: DOM mit Styles → positionierte Text-Runs (Display List)
ui/                     Package ui: raylib-Fenster, Komponenten, Rendering
  main_window.odin        MainWindow, init/destroy, Haupt-Loop (run)
  address_bar.odin        Adressleiste: Eingabe, Fokus, Enter → Callback
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

1. `main` baut `ui.WindowSettings` (1024×768, „Browser“) und ruft `browser.init`.
2. `browser.init` initialisiert zuerst `ui.init` (raylib-Fenster, resizable, Font, AddressBar, PageView), dann `http.init` (curl-Handle + zwei `strings.Builder`). Schlägt HTTP fehl, wird die UI wieder abgebaut.
3. `browser.register_callbacks` setzt `on_url_submit` und `on_link_click` (jeweils mit `_ctx` = Pointer auf den `Browser`) im `MainWindow`. Das ist der Mechanismus, mit dem die UI nach oben kommuniziert, ohne `browser`/`http` zu importieren.
4. `browser.run` → `ui.run`: klassischer raylib-Loop pro Frame:
   - Resize → `address_bar_handle_resize`, `page_view_handle_resize`
   - `address_bar_handle_input` (Klick-Fokus, Zeichen, Backspace, Enter, Escape)
   - `page_view_handle_mouse` (Hand-Cursor über Links, Linksklick → `on_link_click`)
   - Mausrad → `page_view_handle_scroll`
   - `BeginDrawing` → `page_view_render`, dann `address_bar_render` (Adressleiste liegt oben drüber) → `EndDrawing`
   - `free_all(context.temp_allocator)` am Frame-Ende
5. Enter in der Adressleiste → Callback → `load_page`: merkt sich die URL (`current_url`), `http.get` (blockierend, folgt Redirects). Nach einem Redirect werden `current_url` und Adressleiste auf `response.url` gesetzt. Bei `Content-Type: text/html` → `dom.parse` → `page_view_set_document` (PageView übernimmt das Dokument), sonst `page_view_set_content` (Body bzw. Fehlertext → `dom.from_plain_text`). Beim Rendern baut die PageView bei Bedarf das Layout (`layout.build`) und zeichnet die Runs.
6. Klick auf einen Link → `on_link_click(href)` → `http.resolve_url(current_url, href)` → nur `http(s)` wird geladen (`navigate`), `mailto:` usw. werden ignoriert.

### Abhängigkeitsrichtung

`main` → `browser` → (`ui`, `http`, `dom`); `http` → `vendor/curl`; `ui` → `layout` → `dom` → `vendor/lexbor`. `ui` kennt weder `browser` noch `http`. Diese Richtung beibehalten; neue Kommunikation von UI nach oben über Callbacks mit `rawptr`-Context.

### Package-Details

**http** ([http/client.odin](http/client.odin))
- `Client` hält ein wiederverwendetes curl-Easy-Handle (curl macht Connection-Reuse intern) und je einen Builder für Header und Body.
- `header_value(raw, name)` sucht einen Header (case-insensitive); bei Redirects gewinnt der letzte Treffer.
- `resolve_url(base, ref)` nutzt curls URL-API (`curl_url_set` auf eine gesetzte URL löst relativ auf, RFC 3986). Die Binding von `url_get` war fehlerhaft (`-> ^Ucode`), korrigiert auf `-> Ucode` mit `part: ^cstring`; das Ergebnis mit `curl.free` freigeben.
- `get` folgt Redirects (`FOLLOWLOCATION`, max. `MAX_REDIRECTS` = 10); `Http_Response.url` ist die End-URL (`CURLINFO_EFFECTIVE_URL`, gehört curl, gültig bis zum nächsten `get`).
- `get` resettet beide Builder, setzt URL/Callbacks/Timeout (`STANDARD_READ_TIMEOUT` = 30 s) und führt `easy_perform` aus.
- `write_callback` ist `proc "c"` und setzt `context = runtime.default_context()`, bevor in den Builder geschrieben wird.
- Rückgabe `Http_Response{header, body}` – die Strings **zeigen in die Builder des Clients**, sind also nur bis zum nächsten `get` gültig.
- Fehler: `Maybe(Http_Error)` mit curl-Code und `easy_strerror`-Text.

**ui**
- `MainWindow` besitzt `AddressBar`, `PageView`, den Submit- und den Link-Callback. `page_view_handle_mouse` kopiert den Link vor dem Callback in den Temp-Allocator, weil das Laden der neuen Seite das Layout (und damit den String) zerstört.
- `AddressBar`: Text in einem `strings.Builder`; Eingabefeld ist ein fest positioniertes Rect (x = 80, 80 px links/rechts für spätere Buttons reserviert). Fokusfarbe Blau `{66,133,244}`.
- `PageView`: `rect` unterhalb der Adressleiste, `document` (gehört der PageView: `page_view_set_document` übernimmt es, `page_view_set_content` verpackt Text per `dom.from_plain_text`), `page_layout` (gecacht, `page_view_ensure_layout` baut nur neu, wenn sich die Breite ändert), `scroll_y`, `content_height` (= Layout-Höhe). `page_view_render` zeichnet nur Runs im sichtbaren Bereich (Scissor-Mode). `measure_text` ist die `Measure_Text`-Proc für das Layout (raylib). Fette Runs werden mit `font_bold` gezeichnet und gemessen (`font_for(bold)`). Scrollen wird auf `[0, content_height - rect.height]` begrenzt (`clamp_scroll`).
- `font` und `font_bold` sind Package-globale Variablen (`fonts_init` lädt beide, Pfade in `FONT_REGULAR_PATH`/`FONT_BOLD_PATH`), jeweils einmal mit `FONT_LOAD_SIZE` (64) gerastert und beim Zeichnen auf die jeweilige Größe skaliert; Mipmaps + trilinearer Filter halten kleinen Text glatt. Geladen werden die Codepoints aus `font_codepoints` (ASCII, Latin-1, typografische Zeichen).

**dom** ([dom/](dom/))
- `parse(html) -> (^Document, Maybe(Parse_Error))`: parst mit lexbor, kopiert rekursiv in eigene `Node`s und zerstört das lexbor-Dokument sofort. Danach zeigt nichts mehr in lexbors Speicher.
- `Node`: `kind` (`Document`/`Element`/`Text`/`Comment`), `parent`, `children` (`[dynamic]^Node`), `tag` (lowercase), `attributes` (`[]Attribute`, Quellreihenfolge), `text`, `style` (nur Elemente). Doctype und Processing Instructions werden weggelassen.
- Speicher: Ein `virtual.Arena` pro `Document`, alle Nodes und Strings liegen darin; `destroy` gibt alles auf einmal frei.
- lexbor ergänzt fehlendes `<html>`/`<head>`/`<body>` wie ein echter Browser.
- Styles (`Style`: `display`, `color` (eigener Typ `Color :: [4]u8`, kein raylib), `font_size` in px, `font_weight` 1..1000): `parse` ruft `lxb_style_init` vor dem Parsen auf; der Document-Node hat `ROOT_STYLE` (schwarz, 16 px, 400). Pro Element in drei Schritten wie im Browser:
  1. vererbte Properties (`color`, `font-size`, `font-weight`) vom Eltern-Node, `display` nicht,
  2. `default_style(tag, hidden, parent)`: unser vereinfachtes UA-Stylesheet (Block-Tags, `li` = `List_Item`, `head`/`script`/… und `hidden` = `None`, `h1`–`h6` Größe + fett, `b`/`strong` fett, `small` kleiner, `a` = `LINK_COLOR`),
  3. `apply_declaration` für jede Property aus `STYLE_PROPERTIES`, die lexbors Kaskade liefert. Unbekannte Werte werden ignoriert (Default bleibt). `inherit`/`initial`/`unset` werden behandelt.
- lexbor serialisiert normalisiert (lowercase, `#F00` → `#f00`, Kommas vereinheitlicht), lässt relative Einheiten (`em`, `%`, `smaller`, `bolder`) aber stehen – die rechnen wir gegen den Eltern-Style um. Unterstützt: Farben benannt (Teilmenge), Hex, `rgb()`/`rgba()`, `transparent`, `currentcolor` (kein `hsl()`); Größen `px`, `em`, `rem`, `%`, `pt`, Schlüsselwörter; Gewichte `normal`/`bold`/Zahl/`bolder`/`lighter`. Nicht unterstützte Layout-Modi fallen bei `display` auf ihr äußeres Verhalten zurück.

**layout** ([layout/layout.odin](layout/layout.odin))
- `build(doc, width, measure) -> ^Layout` liefert `runs: [dynamic]Text_Run` (`text`, `x`, `y` = linke obere Ecke, `width`, `font_size`, `bold`, `color`, `link` = `href` des umgebenden `<a>`, roh wie in der Seite) und `height`; `link_at(l, x, y)` findet den Link unter einem Punkt (ganze Zeilenbox zählt). Runs werden an Link-Grenzen getrennt. `destroy` gibt alles frei (eine Arena pro Layout).
- Kennt keine Fonts: Textbreite kommt über `Measure_Text`; die UI übergibt raylib, die Tests `fake_measure` (Zeichen × Größe × 0,5) für exakte Erwartungen.
- Vereinfachtes Block-/Inline-Layout: Block-Elemente untereinander mit Default-Margins (`vertical_margin`, in em) und **Margin-Collapsing** (`pending_margin` = max), 8 px Seitenrand (`PAGE_MARGIN`), 40 px Einzug für `ul`/`ol`/`blockquote`/`dd`, Listen-Marker (`•` bzw. `1.`) hängend links. Inline-Text wird an Wörtern umgebrochen, gleich gestylte Wörter einer Zeile werden zu einem Run zusammengefasst (`can_extend`). Zeilenhöhe = größte Schrift × 1,25, kleinere Schrift sitzt unten.
- `<br>` beendet die Zeile (auf leerer Zeile: Leerzeile). In `<pre>` bleiben Leerzeichen/Umbrüche erhalten, lange Zeilen brechen trotzdem um (wie `pre-wrap`); Tabs = 4 Leerzeichen. Fett ab `font_weight >= 600`.

**vendor/lexbor** ([vendor/lexbor/lexbor.odin](vendor/lexbor/lexbor.odin))
- Opake Typen `Html_Document` und `Dom_Node`, `Status`/`STATUS_OK`, `Dom_Node_Type`; Funktionen `lxb_html_document_create/parse/destroy`, `lxb_html_document_body_element_noi` und die Traversal-Procs `lxb_dom_node_{first_child,last_child,next,prev,parent,type}_noi`. `document_node` castet ein Dokument zum Node (wie lexbors `lxb_dom_interface_node`). Genutzt werden die `_noi`-Varianten, weil die normalen Funktionen `static inline` sind.
- Node-Daten: opake `Dom_Element`/`Dom_Attr`; `element_from_node` castet nur Element-Nodes (sonst `nil`). Helper `element_name`, `element_attribute` (über `lxb_dom_element_attr_by_name`, weil `get_attribute` „fehlt“ und „ohne Wert“ nicht unterscheidet), `attr_name`/`attr_value`, `node_text_content`.
- Speicher: Namen und Attributwerte zeigen in lexbors Speicher und gelten, solange das Dokument lebt. `node_text_content` liefert dagegen eine Kopie (Caller gibt frei), weil lexbor den Text separat allokiert und wir ihn sofort mit `lxb_dom_document_destroy_text_noi` freigeben.
- Noch nicht in `main`/`browser` eingebunden.
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
4. **HTTP blockiert den UI-Thread** bis zu 30 s (Timeout). Lösung ist Stage 5.
5. `http.init` prüft nicht, ob `curl.easy_init()` `nil` liefert; `curl_global_init` wird nicht explizit aufgerufen (wichtig, sobald Threads dazukommen).
6. ~~`ui.destroy` gibt den `strings.Builder` der Adressleiste nicht frei~~ – behoben.
7. `address_bar_render` allokiert pro Frame eine cstring auf dem Heap (könnte Temp-Allocator nutzen).
8. Fokus-Klick prüft die ganze Adressleiste statt nur das Eingabefeld.
9. ~~Textumbruch läuft jeden Frame neu~~ – behoben: Das Layout wird gecacht und nur bei Breiten- oder Inhaltsänderung neu gebaut.
10. ~~lexbor auf Windows~~ – behoben: wird von `setup.ps1` aus dem Submodul `vendor/lexbor-src` statisch gebaut. Weil Odin standardmäßig die statische CRT (`libcmt`) linkt, setzt das Binding wie `vendor:raylib` `/NODEFAULTLIB:libcmt` (sonst scheitert `odin test vendor/lexbor` an `__imp__dsign`).
11. URL-Eingabe ohne Schema (`example.com`) wird nicht automatisch zu `http(s)://` ergänzt (steht als TODO in der Roadmap).
12. Linux ist bisher weder dokumentiert noch getestet.
13. ~~Nicht-ASCII-Zeichen werden als `?` gezeichnet~~ – behoben: `fonts_init` lädt ASCII, Latin-1 und ein paar typografische Zeichen (`– „“ … €`). Andere Schriften (z. B. Kyrillisch, CJK) erscheinen weiterhin als `?`; dafür bräuchte es Glyphen bei Bedarf.
14. ~~Zeilenumbrüche im Inhalt gehen verloren~~ – behoben: Plain Text läuft als `<pre>` durchs Layout, Umbrüche bleiben erhalten.

## Roadmap (Kurzfassung, Details im README)

- Stage 1 HTTP-Client – erledigt
- Stage 2 Fenster & UI – Fenster und Adressleiste stehen; offen: Schema-Ergänzung, Tabs, Navigation (zurück/vor/neu laden)
- Stage 3 Rohtext-Rendering – erledigt (Text, Umbruch, Scrollen)
- Stage 4 HTML & CSS – lexbor-Bindings und eigener DOM-Baum (`dom`) fertig, CSS-Kaskade über lexbor gebunden; `display`, `color`, `font-size`, `font-weight` werden berechnet (Vererbung + Defaults + CSS); Package `layout` erzeugt positionierte Text-Runs, die UI zeichnet sie mit Größe, Fett (Inter Bold) und Farbe. Links sind klickbar (relative URLs über curl). Offen: Hintergründe/Boxen, Flexbox & Co.
- Stage 5 Threads – HTTP in eigenen Thread, Ergebnis-Übergabe an die UI, Thread-Sicherheit des Clients
- Stage 6 JavaScript – QuickJS anbinden
