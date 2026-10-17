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
odin test vendor/lexbor    # Lexbor-Smoke-Test
```

**Immer aus dem Repo-Root starten**: Der Font wird über den relativen Pfad `assets/fonts/Inter_18pt-Regular.ttf` geladen ([ui/main_window.odin](ui/main_window.odin)).

Stand 2026-10-17 auf macOS: `odin check .`, `odin build .` und `odin test vendor/lexbor` laufen erfolgreich durch.

### Abhängigkeiten pro Plattform

| Lib | macOS | Windows | Linux |
|---|---|---|---|
| libcurl | `brew install curl mbedtls`, gelinkt als `system:curl` + mbedtls + zlib + `SystemConfiguration.framework` | statisch aus Submodul `vendor/curl-src` (curl-8_14_0) gebaut via [setup.ps1](setup.ps1), Schannel für TLS, `/MD`-CRT | `system:curl` + mbedtls + zlib (ungetestet) |
| raylib | `vendor:raylib` (mit Odin ausgeliefert) | dito | dito |
| lexbor | `brew install lexbor`, `system:lexbor` | **noch nicht verdrahtet** | **noch nicht verdrahtet** |

**Warum curl selbst gebaut wird (Windows):** Odins `vendor:curl` bringt eine Lib mit, deren CRT-Einstellung mit `vendor:raylib` kollidiert. Deshalb liegt eine Kopie der Odin-curl-Bindings unter [vendor/curl/](vendor/curl/) (Package `vendor_curl`), die auf Windows gegen `vendor/curl-src/build/lib/Release/libcurl.lib` linkt. `setup.ps1` braucht CMake und die VS Build Tools (Generator `"Visual Studio 18 2026"`). Build-Artefakte (`vendor/curl-src/build/`, `vendor/curl/lib/`, `*.exe`, `*.dll`) sind in `.gitignore`.

## Projektstruktur

```
main.odin               Einstiegspunkt: WindowSettings → browser.init → register_callbacks → run
browser/browser.odin    Package browser: verbindet UI und HTTP-Client (Orchestrierung)
http/client.odin        Package http: synchroner GET über libcurl easy-API
ui/                     Package ui: raylib-Fenster, Komponenten, Rendering
  main_window.odin        MainWindow, init/destroy, Haupt-Loop (run)
  address_bar.odin        Adressleiste: Eingabe, Fokus, Enter → Callback
  page_view.odin          Seitenansicht: Textumbruch, Scrollen, Rendering
  fonts.odin              globaler Font (fonts_init/fonts_close)
  constants.odin          UI-Konstanten (Höhen, Fontgröße, Scroll-Speed)
vendor/curl/            eigene Kopie der Odin-curl-Bindings (Package vendor_curl) + C-Header
vendor/curl-src/        git-Submodul: curl-Quellcode (nur für den Windows-Build)
vendor/lexbor/          minimale lexbor-Bindings + Test
assets/fonts/           Inter 18pt Regular (OFL-Lizenz)
setup.ps1               Windows-Setup (curl bauen)
```

Import-Pfade sind relativ, z. B. `import "../ui"`, `import "../vendor/curl"`.

## Architektur

### Ablauf

1. `main` baut `ui.WindowSettings` (1024×768, „Browser“) und ruft `browser.init`.
2. `browser.init` initialisiert zuerst `ui.init` (raylib-Fenster, resizable, Font, AddressBar, PageView), dann `http.init` (curl-Handle + zwei `strings.Builder`). Schlägt HTTP fehl, wird die UI wieder abgebaut.
3. `browser.register_callbacks` setzt `on_url_submit` + `on_url_submit_ctx` (Pointer auf den `Browser`) im `MainWindow`. Das ist der Mechanismus, mit dem die UI nach oben kommuniziert, ohne `browser`/`http` zu importieren.
4. `browser.run` → `ui.run`: klassischer raylib-Loop pro Frame:
   - Resize → `address_bar_handle_resize`, `page_view_handle_resize`
   - `address_bar_handle_input` (Klick-Fokus, Zeichen, Backspace, Enter, Escape)
   - Mausrad → `page_view_handle_scroll`
   - `BeginDrawing` → `page_view_render`, dann `address_bar_render` (Adressleiste liegt oben drüber) → `EndDrawing`
   - `free_all(context.temp_allocator)` am Frame-Ende
5. Enter in der Adressleiste → Callback → `http.get` (blockierend) → `page_view.content = response.body` bzw. Fehlertext.

### Abhängigkeitsrichtung

`main` → `browser` → (`ui`, `http`); `http` → `vendor/curl`. `ui` kennt weder `browser` noch `http`. Diese Richtung beibehalten; neue Kommunikation von UI nach oben über Callbacks mit `rawptr`-Context.

### Package-Details

**http** ([http/client.odin](http/client.odin))
- `Client` hält ein wiederverwendetes curl-Easy-Handle (curl macht Connection-Reuse intern) und je einen Builder für Header und Body.
- `get` resettet beide Builder, setzt URL/Callbacks/Timeout (`STANDARD_READ_TIMEOUT` = 30 s) und führt `easy_perform` aus.
- `write_callback` ist `proc "c"` und setzt `context = runtime.default_context()`, bevor in den Builder geschrieben wird.
- Rückgabe `Http_Response{header, body}` – die Strings **zeigen in die Builder des Clients**, sind also nur bis zum nächsten `get` gültig.
- Fehler: `Maybe(Http_Error)` mit curl-Code und `easy_strerror`-Text.

**ui**
- `MainWindow` besitzt `AddressBar`, `PageView` und den Submit-Callback.
- `AddressBar`: Text in einem `strings.Builder`; Eingabefeld ist ein fest positioniertes Rect (x = 80, 80 px links/rechts für spätere Buttons reserviert). Fokusfarbe Blau `{66,133,244}`.
- `PageView`: `rect` unterhalb der Adressleiste, `content` (roher Text), `scroll_y`, `content_height`. `wrap_text` bricht wortweise mit `rl.MeasureTextEx` um und arbeitet komplett im Temp-Allocator. Rendering mit Scissor-Mode. Scrollen wird auf `[0, content_height - rect.height]` begrenzt.
- `font` ist eine Package-globale Variable (geladen mit Größe 32, gezeichnet mit `FONT_SIZE` 16).

**vendor/lexbor** ([vendor/lexbor/lexbor.odin](vendor/lexbor/lexbor.odin))
- Opaker Typ `Html_Document`, `Status`/`STATUS_OK`, Funktionen `lxb_html_document_create/parse/destroy`. Noch nicht in `main`/`browser` eingebunden.
- Nächste Schritte laut Roadmap: DOM-Traversal (first_child, next sibling), Node-Daten (Tag-Name, Text, Attribute), dann eigener DOM-Baum.

## Code-Konventionen

- Einrückung mit Tabs (Odin-Standard), Struct-Felder ausgerichtet.
- Packages = Ordner, ein Konzept pro Datei.
- Procs in `snake_case`, innerhalb eines Packages mit Komponenten-Präfix: `address_bar_init`, `page_view_render`, `fonts_close`. Package-Lebenszyklus-Procs heißen schlicht `init` / `destroy` / `run` (Aufruf dann `ui.init`, `http.get`).
- Typen: bisher gemischt (`MainWindow`, `AddressBar`, `PageView` vs. `Http_Error`, `Http_Response`, `Html_Document`). Für neuen Code `Ada_Case` (Odin-Konvention) bevorzugen bzw. sich am jeweiligen Package orientieren.
- Konstanten in `SCREAMING_SNAKE_CASE`, UI-weite Werte in [ui/constants.odin](ui/constants.odin).
- Fehlerbehandlung: Fehler als zweiter Rückgabewert `Maybe(XxxError)`, Prüfung mit `if err, ok := err.?; ok { … }`. Kein Panic für erwartbare Fehler. Bei Teil-Initialisierung bereits erstellte Ressourcen wieder freigeben.
- Speicher: Frame-lokale Allokationen (cstrings fürs Zeichnen, Textumbruch) über `context.temp_allocator`; der wird am Ende jedes Frames in `ui.run` geleert. Langlebiges explizit mit `defer delete(...)` bzw. in `destroy` freigeben.
- C-Interop: `strings.clone_to_cstring` für Strings an C; C-Callbacks als `proc "c"` mit gesetztem Context.
- Kommentare kurz und auf Englisch, erklären das *Warum*.

## Bekannte Probleme und offene Punkte

Beim Durchsehen aufgefallen (Stand 2026-10-17), noch nicht behoben:

1. **Dangling-String bei HTTP-Fehlern**: `register_callbacks` setzt `page_view.content = fmt.tprintf(...)`. Das liegt im Temp-Allocator, der am Ende jedes Frames per `free_all` geleert wird. Ab dem nächsten Frame zeigt `content` auf freigegebenen Speicher. Fix: Fehlertext mit dem normalen Allocator erzeugen und Ownership von `content` klären.
2. **Body-Lebensdauer**: `content = response.body` zeigt in den Builder des HTTP-Clients. Funktioniert, solange nur ein `get` gleichzeitig läuft, wird aber spätestens mit Threads (Stage 5) zum Problem. Besser: `PageView` besitzt eine eigene Kopie.
3. **Backspace entfernt ein Byte statt einer Rune** ([ui/address_bar.odin](ui/address_bar.odin)) → kaputtes UTF-8 bei Umlauten. Fix z. B. mit `utf8.decode_last_rune_in_string`.
4. **HTTP blockiert den UI-Thread** bis zu 30 s (Timeout). Lösung ist Stage 5.
5. `http.init` prüft nicht, ob `curl.easy_init()` `nil` liefert; `curl_global_init` wird nicht explizit aufgerufen (wichtig, sobald Threads dazukommen).
6. `ui.destroy` gibt den `strings.Builder` der Adressleiste nicht frei.
7. `address_bar_render` allokiert pro Frame eine cstring auf dem Heap (könnte Temp-Allocator nutzen).
8. Fokus-Klick prüft die ganze Adressleiste statt nur das Eingabefeld.
9. `wrap_text` läuft jeden Frame neu über den ganzen Text und misst jeden Kandidaten → bei großen Seiten langsam. `content_height` wird erst beim Rendern berechnet. Kandidat für Caching bei Content- oder Breitenänderung.
10. **lexbor-Binding**: `lxb_html_document_destroy` gibt in C `lxb_html_document_t *` zurück, die Odin-Signatur deklariert `Html_Document` als Wert → sollte `^Html_Document` sein. Außerdem existiert `foreign import lib` nur für Darwin, d. h. auf Windows/Linux kompiliert das Package nicht, sobald es importiert wird.
11. URL-Eingabe ohne Schema (`example.com`) wird nicht automatisch zu `http(s)://` ergänzt (steht als TODO in der Roadmap).
12. Linux ist bisher weder dokumentiert noch getestet.

## Roadmap (Kurzfassung, Details im README)

- Stage 1 HTTP-Client – erledigt
- Stage 2 Fenster & UI – Fenster und Adressleiste stehen; offen: Schema-Ergänzung, Tabs, Navigation (zurück/vor/neu laden)
- Stage 3 Rohtext-Rendering – erledigt (Text, Umbruch, Scrollen)
- Stage 4 HTML & CSS – lexbor-Grundbindings fertig; nächster Schritt: DOM-Traversal und Node-Daten
- Stage 5 Threads – HTTP in eigenen Thread, Ergebnis-Übergabe an die UI, Thread-Sicherheit des Clients
- Stage 6 JavaScript – QuickJS anbinden
