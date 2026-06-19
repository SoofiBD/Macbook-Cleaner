# Glass Cleanup — UI Redesign Design

**Date:** 2026-06-18
**Status:** Approved for planning

## Goal

Reskin the existing "Apple Cleanup" macOS maintenance web app to the
"Glass Cleanup" glassmorphism design language, convert all copy from Turkish to
English, default to dark theme, and layer rich GSAP motion on top — **without
removing any existing feature or changing backend behavior**.

The design reference is `Glass Cleanup.html` (a component mockup). Its extracted
markup/tokens are the visual source of truth.

## Constraints (what must NOT change)

- `web/server.py` and all API endpoints (`/api/scan`, `/api/clean`, etc.)
- Scan/clean business logic and the cleanup token mechanism
- HTML element IDs and the DOM contract `script.js` relies on
- The three tabs (Cleanup / App Uninstaller / Files), terminal drawer, results
  panel, and all 5 maintenance tools — all retained, only restyled
- `clean_mac.sh` and tests

## Decisions

| Decision | Choice |
|---|---|
| Scope | Restyle the **whole** app; keep all features |
| Animation | **Rich** GSAP motion (already vendored) |
| Default theme | **Dark** |
| Language | **English** everywhere (was Turkish) |

## 1. Visual foundation — `web/style.css` token layer

Replace the current flat token set with the mockup's glass tokens, providing a
full set for **both** themes (mockup supplies both):

- `--glass`, `--glass-bd`, `--glass-shadow`, `--glass-blur`
- `--chip`, `--hair`, `--check-bd`
- `--wall` — multi-radial gradient "wallpaper" (`background-attachment: fixed`)
- `--blob-a/b/c`, `--blob-alpha`
- `--donut-track`
- Keep accent `#2466e8` / `#4d8eff` (shared by both designs).

`<html>` gets `data-theme="dark"` as the default; the existing theme toggle still
swaps to light. The token cascade stays keyed on `[data-theme="..."]` so
`script.js`'s toggle keeps working unchanged.

Glass surface recipe (applied to every panel):
`background: var(--glass)` + `backdrop-filter: blur(var(--glass-blur))
saturate(180%)` (with `-webkit-` prefix) + `1px solid var(--glass-bd)` border +
`var(--glass-shadow)` (drop shadow + inset top highlight) + generous radii.

### Background blob layer

Add a single fixed, `pointer-events:none`, `z-index:0` container near the top of
`.app` (or `body`) holding three large blurred radial blobs. Content sits above
at `z-index:1`. Blob drift is driven by GSAP (see §3), with a CSS
`@keyframes float*` fallback for the no-JS / reduced-motion path.

## 2. Component restyle (all features kept)

Each existing component is restyled to glass; IDs and structure preserved.
Minimal HTML edits — only adding the blob layer and any wrappers strictly needed.

- **Topbar**: glass bar; gradient brand mark tile; sysbar chips → pill chips with
  `--chip` bg + `--hair` border; disk mini-bar gradient; glass theme toggle.
- **Nav tabs**: glass segmented pill control; active tab gets accent-tinted fill.
- **Hero**: glass card with `rise` entrance; eyebrow accent pill; large title;
  lead; big number; primary button (accent gradient + glow + inset highlight);
  accent "Clean" button (accent-tinted glass); dry-run toggle; disk donut with
  gradient stroke + rounded cap over `--donut-track`.
- **Categories**: glass container; rows with custom check box (`--check-bd` →
  accent fill + white check when selected), accent-tinted icon tile, size label;
  selected row gets accent-tint background. Select all / Clear chip buttons.
- **Results panel**: accent-tinted glass banner (check badge, freed value, close).
- **Maintenance**: glass rows; neutral icon tile; ghost action buttons; "Done"
  state in success green.
- **Uninstaller tab**: glass list rows + glass search box.
- **Files tab**: glass toolbar (search, sort select, select buttons), glass list
  rows, glass footer with total + accent clean button.
- **Terminal drawer**: glass header; body keeps dark terminal palette.
- **Footer**: shield icon + muted text, restyled to glass-era muted tokens.

## 3. Rich GSAP motion — `web/anim.js`

Extend the existing `AppAnim` layer (keep its fail-safe stub + reduced-motion
guards via `gsap.matchMedia`):

- **Blobs**: replace CSS `floatA/B/C` with GSAP infinite `yoyo` tweens on `x/y`
  for organic drift (transforms only, per gsap-performance).
- **Intro**: glass cards rise + fade in with stagger (enhances current
  `intro()`); use `autoAlpha`, transform aliases, `power3.out`.
- **Disk donut**: animate `stroke-dasharray` sweep + number count-up on load and
  after scan (extends `afterScan()`).
- **Theme toggle**: quick cross-fade/scale pulse on the app shell when switching.
- **Retained as-is**: `revealCards` (ScrollTrigger batch), `flipApps` (Flip),
  `expand`, Draggable terminal/results, `pop`.

All motion respects `prefers-reduced-motion` (collapses to final state).

## 4. Language conversion — Turkish → English

Translate all user-facing copy:

- **`web/index.html`** (~45 lines): brand sub, tab labels, hero copy, section
  titles/subs, button labels, maintenance card names/descriptions, terminal,
  footer, `lang="tr"` → `lang="en"`, `aria-label`s, placeholders.
- **`web/script.js`** (~459 lines with Turkish): category names/descriptions,
  status/eyebrow strings, phase labels (Scan / Scanning… / Clean now /
  Cleaning… / Preview), counts ("X of Y selected"), results copy, error
  messages, toasts, terminal log lines, app-uninstaller and files-tab strings.

Wording follows the English mockup where equivalents exist (e.g. "Scan",
"Clean now", "Preview only", "Categories", "Select all", "Clear", "System
maintenance", "disk used", "Nothing is deleted without your confirmation").
Number/byte formatting helpers are unchanged. No string IDs/keys change — only
displayed text.

## Files touched

- `web/style.css` — token overhaul + component restyle (largest change)
- `web/index.html` — `data-theme="dark"`, blob layer, English static copy
- `web/anim.js` — blob/donut/theme/intro motion additions
- `web/script.js` — English dynamic copy (no logic change)
- (No server, test, or shell changes.)

## Testing / verification

- Load the app via the existing server; confirm dark glass renders, blobs drift,
  intro plays, donut sweeps.
- Run scan → categories populate, sizes count up, hero number tweens.
- Run clean (dry-run + real) → results banner; numbers update.
- Toggle theme → light glass renders correctly; toggle persists as before.
- Exercise all three tabs, terminal drawer, maintenance buttons.
- Verify `prefers-reduced-motion` collapses animation.
- Confirm no remaining Turkish characters in `index.html` / `script.js` user copy.
- Existing test suite still passes (no backend change expected).
