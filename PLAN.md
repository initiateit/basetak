# basetak

## Goal

A minimal and blazing-fast Windows 11 panel bar serving as a taskbar replacement, built in Rust
with raw Win32/DWM integration, first-class Mica support, TOML configuration, and a native CSS
engine with animations, transitions, and basic filters — targeting ~10–20 MB RAM.

## Decided Architecture (2026-09-04)

| Decision        | Choice                                                                 |
|-----------------|------------------------------------------------------------------------|
| Rendering       | Native: custom CSS parser + Direct2D/DirectComposition renderer        |
| Bar mode        | AppBar (`SHAppBarMessage`) alongside Windows taskbar; no tray takeover |
| Backdrop         | Acrylic default. The bar is a `WS_EX_LAYERED` per-pixel-alpha window presented with `UpdateLayeredWindow`; `acrylic` and `mica` enable the legacy DWM accent blur (`ACCENT_ENABLE_ACRYLICBLURBEHIND`, theme-tinted — works while unfocused, unlike `DWMWA_SYSTEMBACKDROP_TYPE` materials which DWM only composites for the active window): acrylic is the classic frosted look, mica uses a heavier tint as a milky approximation of the opaque DWM Mica material, and `none` leaves the layer fully transparent. Theme-following via `style.css` / `style-dark.css` + tint colors. |
| Widgets         | Compiled-in Rust modules (static `Widget` trait)                       |
| CSS scope       | Lean subset **plus** `@keyframes`, `transition`, `filter`, `transform` |
| Monitors        | Primary monitor only in v1; per-monitor bars later                     |
| Windowing       | Raw `windows-rs` FFI — no GUI toolkit                                  |
| Renderer        | Direct2D + DirectComposition (native DWM/Mica + blur/effects support)  |

### Core crates

- `windows` — Win32, DWM, Shell (AppBar), Shell hook, WinRT (GSMTC, VD manager)
- `serde` + `toml` — config
- `notify` — file watching for hot reload
- CSS engine, layout, widget framework — hand-written

## Architecture Overview

```
main.rs ─┬─ config/       TOML load + hot reload (notify)
         ├─ window/       Win32 window, AppBar registration, DWM/Mica backdrop
         ├─ css/          lexer → parser → stylesheet → cascader
         ├─ layout/       flexbox (row/column) layout tree → render tree
         ├─ render/       Direct2D draw + DirectComposition animations/effects
         ├─ shell/        WinEvent hook (foreground window), WinRT media, VD
         └─ widgets/      built-in widgets implementing Widget trait
```

### Widget trait (v1 contract — designed so a dylib/WASM loader can slot in later)

```rust
trait Widget {
    fn init(cfg: &TomlValue, ctx: &WidgetCtx) -> Result<Self>;
    fn render(&mut self) -> Node;                 // declarative node tree
    fn on_event(&mut self, e: Event);             // mouse/hover/click/shell events
    fn interval(&self) -> Option<Duration>;       // polling tick (clock, media)
}
```

## CSS subset (v1)

**Supported:** selectors (tag, `.class`, descendant, `:hover`); `display: flex`
(row/column); box model (margin/padding/gap); `background` (`rgba`); `border-radius`;
`position: absolute` overlays; `color`; `font-family` / `font-size` / `font-weight`
(400/600) / `letter-spacing`; px/% units; `filter: blur() brightness() saturate()`;
`backdrop-filter: blur() brightness() saturate()` (blurs in-layer content behind an
element).

**Deferred:** grid, pseudo-elements, `@media`, full selector combinators, box-shadow,
`transition`, `@keyframes` + `animation`, `transform`, `opacity` property.

## TOML config sketch

```toml
[bar]
position = "top"          # top | bottom
height = 48
backdrop = "mica"         # mica | acrylic | none
islands = true            # per-widget styling vs full-width bar

[[widget]]
type = "active_window"
style = "active_window.css"

[[widget]]
type = "clock"
format = "%a %d %b  %H:%M"
style = "clock.css"

[[widget]]
type = "media"            # WinRT GSMTC
style = "media.css"

[[widget]]
type = "virtual_desktops" # IVirtualDesktopManager
style = "vd.css"
```

## Build Phases

### Phase 1 — Window & shell skeleton

- [x] Cargo project, `windows-rs` window creation, message loop
- [x] AppBar registration (`SHAppBarMessage`, ABM_NEW) reserving top/bottom edge
- [x] Per-pixel alpha / transparent window via a `WS_EX_LAYERED` + `UpdateLayeredWindow` surface (D2D renders into a 32-bit DIB that DWM composites per-pixel)
- [x] DWM backdrop rework: `mica`/`acrylic`/`none` via the legacy accent blur (`ACCENT_ENABLE_ACRYLICBLURBEHIND`, theme-tinted) on the layered window — see Backdrop row; the original `DwmSetWindowAttribute` Mica route is unavailable to never-active layered windows
- [x] DPI awareness (per-monitor v2, single monitor)

### Phase 2 — CSS engine core

- [x] Lexer + parser → stylesheet AST (selectors, declarations, `@keyframes`)
- [x] Specificity + cascade resolution
- [x] Lean selector matcher (tag/class/descendant/:hover)
- [x] Unit tests against a golden suite of stylesheets (`tests/golden.rs` + `tests/golden/bar.css`)

### Phase 3 — Layout & renderer

- [x] Flexbox layout engine (row/column, gap, align/justify) + `position: absolute` overlays filling the parent content box
- [x] Direct2D text (DirectWrite: family/weight/size, grayscale AA, letter-spacing), rounded rects, translucent `rgba` backgrounds
- [x] Per-element filters (software): `filter: blur/brightness/saturate` and `backdrop-filter` on in-layer content; GPU/DComp versions pending (Phase 8)
- [ ] Render tree diffing so widget updates don't redraw the whole bar
- [ ] Hit testing + mouse events (hover → `:hover` re-cascade)

### Phase 4 — Widget framework + Clock

- [x] TOML `[[widget]]` loading: `class` (styled in CSS) + built-in `kind`s (`text`, `clock`, `media`)
- [x] Clock widget (local time, strftime-style `time_format`/`date_format`, `.time`/`.date` labels)
- [x] Islands mode (per-widget styled containers) via configured classes
- [x] Media chip demo (album art + glass overlay) proving overlays + `backdrop-filter`
- [ ] Formal `Widget` trait (init / interval / render / on_event) replacing the `kind` match

### Phase 5 — Hot reload

- [x] In-place reload of `config.toml` + stylesheets (mtime poll on the existing 1 s tick; window kept, geometry/backdrop re-applied)
- [ ] `notify`-crate watcher (event-driven, no poll latency)

### Phase 6 — Active Window widget

- [ ] WinEvent hook (`SetWinEventHook` EVENT_SYSTEM_FOREGROUND)
- [ ] HWND → icon extraction (`GetWindowIcon` / SHGetFileInfo cache), pretty name from window class/title
- [ ] Icon rendering pipeline into Direct2D bitmaps

### Phase 7 — Media & Virtual Desktops

- [ ] Media: WinRT `GlobalSystemMediaTransportControlsSessionManager` polling, play/pause events, album-art bitmap
- [ ] VD: `IVirtualDesktopManager` — current desktop indicator + click-to-switch

### Phase 8 — Animations & filters

- [x] `filter: blur()/brightness()/saturate()` and `backdrop-filter` (software, per-element layers)
- [ ] Transition engine (property interpolation on the compositor where possible)
- [ ] `@keyframes` + `animation` scheduling via DirectComposition animations
- [ ] `transform`, GPU effects (D2D/DC effects), compositor-driven off-thread animation

### Phase 9 — Polish & release

- [ ] Multiple monitors (stretch goal — structure already isolated in `window/`)
- [ ] Error handling: config validation messages, graceful degradation per widget
- [ ] README with config docs, screenshots, RAM/perf benchmarks
- [ ] CI (build + test), release binary

## Non-Goals (v1)

- System tray icon hosting (Shell_NotifyIcon takeover)
- Start button / launcher widget
- Plugin/dynamic loading (trait designed for it, no loader)
- Full CSS parity (grid, pseudo-elements, `@media`, box-shadow, transitions on arbitrary properties)

## Widgets in initial scope

- **Active Window** — HWND tracking, app icon extraction, pretty name from window class
- **Clock** — day/date/time, strftime-style format
- **Media / Now Playing** — WinRT GSMTC (Spotify, browsers, etc.)
- **Virtual Desktops** — current desktop indicator + switching
