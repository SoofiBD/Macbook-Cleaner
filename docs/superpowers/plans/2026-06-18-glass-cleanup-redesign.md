# Glass Cleanup Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reskin the existing "Apple Cleanup" web app to the "Glass Cleanup" glassmorphism design, default to dark theme, add rich GSAP motion, and convert all copy from Turkish to English — without changing backend behavior, IDs, or the DOM contract.

**Architecture:** The existing `web/style.css` routes every panel through shared tokens (`--surface`, `--border`, `--shadow-*`). We redefine those tokens to glass values (translucent surfaces, multi-radial `--wall` background, soft glass shadows) so most components turn glass automatically, then add `backdrop-filter` blur + targeted polish to the panel selectors. A fixed background layer of three GSAP-drifting blurred blobs sits behind content. `web/anim.js` (existing `AppAnim` GSAP layer) is extended for blobs, donut sweep, and theme cross-fade. Copy is translated in place in `index.html` and `script.js`.

**Tech Stack:** Static HTML/CSS/vanilla JS; GSAP 3 (vendored locally in `web/vendor/`, already wired); Python stdlib HTTP server (`web/server.py`, untouched).

## Global Constraints

- Do NOT modify `web/server.py`, API endpoints, scan/clean logic, the cleanup-token mechanism, `clean_mac.sh`, or `tests/`.
- Do NOT rename or remove any HTML element `id`, or change the DOM structure `script.js` depends on (only add the blob layer + restyle).
- Keep all three tabs (Cleanup / App Uninstaller / Files), terminal drawer, results panel, and all 5 maintenance tools.
- Accent stays `#2466e8` (light) / `#4d8eff` (dark).
- Default theme is **dark**: `<html ... data-theme="dark">`.
- All user-facing copy in English; no Turkish characters (`çğışöüÇĞİŞÖÜ`) remain in `index.html` or `script.js` display strings. `lang="en"`.
- All motion stays behind `prefers-reduced-motion` (collapse to final state) and behind the existing `AppAnim` GSAP-missing stub.
- Verification is visual/manual + grep (no automated UI test framework exists); run the app via the existing server.

**Run the app for manual checks:** `cd web && python3 server.py` then open the printed `http://127.0.0.1:PORT/?token=...` URL. Stop with Ctrl-C.

---

### Task 1: Glass token layer + dark default + background blobs

**Files:**
- Modify: `web/index.html:2` (html tag), `web/index.html:130` (add blob layer inside `.app`)
- Modify: `web/style.css:6-123` (tokens + background)

**Interfaces:**
- Produces: CSS custom properties `--glass`, `--glass-bd`, `--glass-shadow`, `--glass-blur`, `--chip`, `--hair`, `--check-bd`, `--wall`, `--blob-a/b/c`, `--blob-alpha`, `--donut-track` on `[data-theme]`; markup `<div class="bg-blobs"><span class="blob blob-a"></span>...</div>` with three blobs that Task 6 animates via `gsap.to('.blob-a' ...)`.

- [ ] **Step 1: Set dark default + lang in index.html**

In `web/index.html` line 2, change:
```html
<html lang="tr" data-theme="light">
```
to:
```html
<html lang="en" data-theme="dark">
```

- [ ] **Step 2: Add the background blob layer**

In `web/index.html`, immediately after `<div class="app">` (line 130), insert:
```html
    <!-- ── Glass background blobs (GSAP-animated) ──────────────── -->
    <div class="bg-blobs" aria-hidden="true">
      <span class="blob blob-a"></span>
      <span class="blob blob-b"></span>
      <span class="blob blob-c"></span>
    </div>
```

- [ ] **Step 3: Add glass tokens to both themes in style.css**

In `web/style.css`, inside the `[data-theme="light"]` block (after line 41), add:
```css
  /* Glass */
  --glass:        rgba(255,255,255,.58);
  --glass-bd:     rgba(255,255,255,.72);
  --glass-shadow: 0 10px 34px -12px rgba(28,40,80,.22), inset 0 1px 0 rgba(255,255,255,.8);
  --glass-blur:   30px;
  --chip:         rgba(255,255,255,.5);
  --hair:         rgba(20,30,60,.08);
  --check-bd:     rgba(20,30,60,.24);
  --donut-track:  rgba(20,30,60,.10);
  --wall:
    radial-gradient(1000px 560px at 8% -10%, #d6e4ff 0%, transparent 58%),
    radial-gradient(820px 620px at 98% 6%, #ecdfff 0%, transparent 54%),
    radial-gradient(760px 540px at 58% 116%, #d6f3ff 0%, transparent 56%),
    linear-gradient(180deg,#eef2fb 0%,#f4f1fb 100%);
  --blob-a: #7aa6ff; --blob-b: #c4a9ff; --blob-c: #86e0ff; --blob-alpha: .5;
```
Inside the `[data-theme="dark"]` block (after line 67), add:
```css
  /* Glass */
  --glass:        rgba(26,30,40,.5);
  --glass-bd:     rgba(255,255,255,.1);
  --glass-shadow: 0 16px 46px -16px rgba(0,0,0,.62), inset 0 1px 0 rgba(255,255,255,.09);
  --glass-blur:   30px;
  --chip:         rgba(255,255,255,.06);
  --hair:         rgba(255,255,255,.08);
  --check-bd:     rgba(255,255,255,.24);
  --donut-track:  rgba(255,255,255,.08);
  --wall:
    radial-gradient(1000px 560px at 8% -10%, #15243f 0%, transparent 58%),
    radial-gradient(820px 620px at 98% 6%, #211a3a 0%, transparent 54%),
    radial-gradient(760px 540px at 58% 116%, #0f2a36 0%, transparent 56%),
    linear-gradient(180deg,#0a0d16 0%,#08060f 100%);
  --blob-a: #2f5fd0; --blob-b: #6b3fd0; --blob-c: #1f7fa8; --blob-alpha: .55;
```
Also make the shared surface/border tokens glass-aware so existing components inherit the look. In BOTH theme blocks, change `--surface` to `var(--glass)`, `--border` to `var(--glass-bd)`, and `--hairline` to `var(--hair)`:
```css
  --surface:  rgba(255,255,255,.58);   /* light: same as --glass */
  --border:   rgba(255,255,255,.72);
  --hairline: rgba(20,30,60,.08);
```
(and the dark equivalents `rgba(26,30,40,.5)`, `rgba(255,255,255,.1)`, `rgba(255,255,255,.08)`). Keep `--surface-2`/`--surface-3` as the existing solid values for inner hovers.

- [ ] **Step 4: Replace the body background with the wall + style blobs**

In `web/style.css`, change the `body` `background` (line 107) to `var(--wall)` and add `background-attachment: fixed;`. Replace the `body::before` block (lines 114-123) with the blob layer styles:
```css
body {
  /* ...existing... */
  background: var(--wall);
  background-attachment: fixed;
}
.bg-blobs { position: fixed; inset: 0; z-index: 0; overflow: hidden; pointer-events: none; }
.blob {
  position: absolute; border-radius: 50%; filter: blur(95px);
  opacity: var(--blob-alpha); will-change: transform;
}
.blob-a { width: 540px; height: 540px; background: var(--blob-a); top: -160px; left: -100px; }
.blob-b { width: 480px; height: 480px; background: var(--blob-b); top: -80px; right: -120px; }
.blob-c { width: 460px; height: 460px; background: var(--blob-c); bottom: -160px; left: 40%; }
/* CSS fallback drift when GSAP/JS is unavailable */
html:not(.gsap-on) .blob-a { animation: floatA 20s ease-in-out infinite; }
html:not(.gsap-on) .blob-b { animation: floatB 24s ease-in-out infinite; }
html:not(.gsap-on) .blob-c { animation: floatC 22s ease-in-out infinite; }
@keyframes floatA { 0%,100%{transform:translate(0,0)} 50%{transform:translate(60px,40px)} }
@keyframes floatB { 0%,100%{transform:translate(0,0)} 50%{transform:translate(-50px,30px)} }
@keyframes floatC { 0%,100%{transform:translate(0,0)} 50%{transform:translate(30px,-50px)} }
@media (prefers-reduced-motion: reduce) { .blob { animation: none !important; } }
```
Ensure `.app` sits above blobs: add `position: relative; z-index: 1;` to `.app` (line 139).

- [ ] **Step 5: Verify**

Run: `cd web && python3 server.py`, open the URL. Expected: page loads in **dark** glass with a soft multi-color wall and three blurred blobs visible behind the panels; no console errors. Confirm `grep -c 'data-theme="dark"' index.html` returns `1`.

- [ ] **Step 6: Commit**

```bash
git add web/index.html web/style.css
git commit -m "feat: add glass tokens, dark default, and background blob layer"
```

---

### Task 2: Frosted-glass panels (backdrop-filter) + topbar + nav tabs

**Files:**
- Modify: `web/style.css` (`.topbar` ~151, `.nav-tabs`/`.tab-btn`, `.sys-chip` ~179, `.theme-toggle`)

**Interfaces:**
- Consumes: glass tokens from Task 1.
- Produces: a reusable glass-panel look on `.topbar`, `.hero`, `.cat-list`, `.results`, `.term`, `.nav-tabs` via `backdrop-filter`.

- [ ] **Step 1: Add a shared backdrop-filter to all glass panels**

In `web/style.css`, add one rule (near the top of the components, after `.app`):
```css
/* Frosted glass — applied to every top-level panel */
.topbar, .nav-tabs, .hero, .cat-list, .results, .term, .uninstaller-container {
  -webkit-backdrop-filter: blur(var(--glass-blur)) saturate(180%);
  backdrop-filter: blur(var(--glass-blur)) saturate(180%);
}
```
Update `.topbar` `box-shadow` (line 160) from `var(--shadow-sm)` to `var(--glass-shadow)` and bump `border-radius` to `18px`.

- [ ] **Step 2: Restyle sysbar chips to glass pills**

Change `.sys-chip` background to `var(--chip)`, border to `1px solid var(--hair)`, keep pill radius. The disk mini-bar fill (`.sys-disk-fill`) keeps the accent gradient.

- [ ] **Step 3: Style the nav tabs as a glass segmented control**

Give `.nav-tabs` `background: var(--glass)`, `border: 1px solid var(--glass-bd)`, `box-shadow: var(--glass-shadow)`, `border-radius: 14px`, `padding: 5px`, `gap: 4px`, `display: flex`. Style `.tab-btn` as transparent pills (`border-radius: 10px`, `color: var(--text-2)`), and `.tab-btn.active` with `background: color-mix(in srgb, var(--accent) 14%, transparent); color: var(--accent);`. On hover (non-active): `background: var(--hair);`.

- [ ] **Step 4: Style the theme toggle**

`.theme-toggle`: `background: var(--chip); border: 1px solid var(--glass-bd); border-radius: 11px;`. On hover: `background: color-mix(in srgb, var(--accent) 12%, var(--chip)); color: var(--accent);`.

- [ ] **Step 5: Verify**

Reload app. Expected: topbar/tabs are frosted (content behind them is blurred), tabs read as a segmented control with an accent-tinted active tab, chips are soft pills. Click each tab — switching still works.

- [ ] **Step 6: Commit**

```bash
git add web/style.css
git commit -m "feat: frosted-glass topbar, sysbar chips, and segmented nav tabs"
```

---

### Task 3: Hero + disk donut restyle

**Files:**
- Modify: `web/style.css` (`.hero` ~232, `.hero-eyebrow`, `.hero-number`, `.btn-primary`/`.btn-accent`, `.donut*`)

**Interfaces:**
- Consumes: glass tokens; `#donutFill` (animated by Task 6).

- [ ] **Step 1: Glass hero card**

`.hero`: `background: var(--glass); border: 1px solid var(--glass-bd); box-shadow: var(--glass-shadow); border-radius: 24px;`. Remove/neutralize the old `.hero::after` accent wash if it clashes (keep if subtle). Keep the existing `rise`/intro entrance.

- [ ] **Step 2: Eyebrow pill + buttons**

`.hero-eyebrow`: accent pill — `color: var(--accent); background: color-mix(in srgb, var(--accent) 12%, transparent); border-radius: 999px; padding: 5px 11px; text-transform: uppercase; font-size: 12px; font-weight: 650;`.
`.btn-primary`: `background: linear-gradient(180deg, var(--accent-2), var(--accent)); box-shadow: 0 10px 24px -8px color-mix(in srgb, var(--accent) 65%, transparent), inset 0 1px 0 rgba(255,255,255,.35); border: 1px solid color-mix(in srgb, var(--accent) 55%, transparent); border-radius: 13px;`.
`.btn-accent`: `background: color-mix(in srgb, var(--accent) 16%, var(--glass)); color: var(--accent); border: 1px solid color-mix(in srgb, var(--accent) 32%, transparent); border-radius: 13px;`.

- [ ] **Step 3: Donut**

`.donut-track { stroke: var(--donut-track); }`. Confirm `.donut-fill` uses the existing `url(#...)` accent gradient (or add a `donutGrad` linearGradient from `--accent-2` to `--accent` if not present). Round line cap stays.

- [ ] **Step 4: Verify**

Reload app. Expected: hero is a frosted card; eyebrow is an accent pill; "Tara/Scan" button has a glowing accent gradient; donut track is faint, fill is the accent gradient.

- [ ] **Step 5: Commit**

```bash
git add web/style.css
git commit -m "feat: glass hero, accent buttons, and donut restyle"
```

---

### Task 4: Categories, results banner, maintenance restyle

**Files:**
- Modify: `web/style.css` (`.cat-list` ~488, `.cat-row`, `.cat-ic`, custom checkbox styles, `.results` ~262 area, `.chip-btn`, maintenance rows)

**Interfaces:**
- Consumes: glass tokens; checkbox/selected classes set by `script.js` (`.cat.selected`).

- [ ] **Step 1: Glass category container + rows**

`.cat-list`: `background: var(--glass); border: 1px solid var(--glass-bd); box-shadow: var(--glass-shadow); border-radius: 20px; padding: 7px;`. Rows `.cat-row`: `border-radius: 13px;`, hover `background: var(--hair);`. Replace the `border-top` divider (`.cat + .cat`) with the tighter `gap`-based look (set `.cat-list { gap: 1px }` and remove the hairline border, or keep — implementer's call to match the mockup's seamless rows). Selected row (`.cat.selected .cat-row`): `background: color-mix(in srgb, var(--accent) 9%, transparent);`.

- [ ] **Step 2: Custom check box + icon tile**

The selection check box: `width:21px; height:21px; border-radius:7px; border:1.5px solid var(--check-bd);` unchecked; `.cat.selected` → `border-color: var(--accent); background: var(--accent);` with a white check svg. `.cat-ic`: `background: color-mix(in srgb, var(--accent) 13%, transparent); color: var(--accent); border-radius: 11px;`.

- [ ] **Step 3: Chip buttons (Select all / Clear)**

`.chip-btn`: `background: var(--chip); border: 1px solid var(--glass-bd); border-radius: 9px;`. Hover: `color: var(--accent); border-color: color-mix(in srgb, var(--accent) 35%, transparent);`.

- [ ] **Step 4: Results banner**

`.results`: `background: color-mix(in srgb, var(--accent) 12%, var(--glass)); border: 1px solid color-mix(in srgb, var(--accent) 28%, transparent); box-shadow: var(--glass-shadow); border-radius: 18px;`. The `.results-dot`/badge becomes an accent check badge; freed value in accent color.

- [ ] **Step 5: Maintenance rows**

Maintenance `.cat-maint` rows share the glass list container; icon tiles use neutral `var(--chip)`/`var(--text-2)`; `.btn-ghost` action buttons use `var(--chip)` + `var(--glass-bd)`. "Done" success state keeps green.

- [ ] **Step 6: Verify**

Reload, run a scan. Expected: categories sit in a frosted card, selectable rows tint accent when checked with a filled accent check box and accent icon tiles; Select-all/Clear are glass chips; running a clean shows an accent-tinted glass results banner; maintenance rows match.

- [ ] **Step 7: Commit**

```bash
git add web/style.css
git commit -m "feat: glass categories, results banner, and maintenance restyle"
```

---

### Task 5: Uninstaller, Files tab, terminal, footer restyle

**Files:**
- Modify: `web/style.css` (`.uninstaller-container`, `.apps-list`/`.app-item`, `.search-box`, `.files-*`, `.term*`, `.foot*`)

**Interfaces:**
- Consumes: glass tokens.

- [ ] **Step 1: Search boxes + uninstaller list**

`.search-box`: `background: var(--chip); border: 1px solid var(--glass-bd); border-radius: 10px;`. `.uninstaller-container`/`.apps-list` rows on the glass surface; `.app-item` hover `background: var(--hair);`.

- [ ] **Step 2: Files tab toolbar + list + footer**

`.files-toolbar` controls (search, `.files-sort` select, `.btn-sm`) use `var(--chip)` + `var(--glass-bd)`. `.files-list` rows on glass with `border-radius`; `.files-footer` is a glass bar (`background: var(--glass); border: 1px solid var(--glass-bd); border-radius: 16px;`) with the accent "Clean selected" button (reuse `.btn-accent`).

- [ ] **Step 3: Terminal drawer**

`.term`: `background: var(--glass); border: 1px solid var(--glass-bd); box-shadow: var(--glass-shadow); border-radius: 18px;`. `.term-head` stays glass; `.term-body` keeps the dark `--term-bg` terminal palette for readability.

- [ ] **Step 4: Footer**

`.foot`: muted `var(--text-3)`; keep the shield/info icon in `var(--accent)`. Center, small.

- [ ] **Step 5: Verify**

Reload, click the App Uninstaller and Files tabs. Expected: both lists, search boxes, sort select, and the files footer are glass and legible in dark mode; terminal drawer is glass with a dark log body; footer is muted.

- [ ] **Step 6: Commit**

```bash
git add web/style.css
git commit -m "feat: glass uninstaller, files tab, terminal, and footer"
```

---

### Task 6: Rich GSAP motion (anim.js)

**Files:**
- Modify: `web/anim.js` (add `blobs()`, extend `intro()`, donut sweep, `themeSwitch()`)
- Modify: `web/script.js` (call the new hooks at the right lifecycle points — find existing `AppAnim` call sites)

**Interfaces:**
- Consumes: `.blob-a/b/c` (Task 1), `#donutFill`/`#donutNum` (existing), theme toggle handler in `script.js`.
- Produces: `AppAnim.blobs()`, `AppAnim.themeSwitch()`, donut sweep inside existing `intro()`/`afterScan()`.

- [ ] **Step 1: Animate blobs with GSAP**

In `web/anim.js`, add to the `AppAnim` object (before the closing `}`):
```javascript
    /* Organic infinite drift for the background blobs (transforms only). */
    blobs() {
      if (reduce) return;
      const defs = [
        ['.blob-a', 60, 40, 20],
        ['.blob-b', -50, 30, 24],
        ['.blob-c', 30, -50, 22],
      ];
      defs.forEach(([sel, x, y, dur]) => {
        if (!$(sel)) return;
        g.to(sel, { x, y, duration: dur, ease: 'sine.inOut', repeat: -1, yoyo: true });
      });
    },
```

- [ ] **Step 2: Donut sweep + count-up**

Add to `AppAnim`:
```javascript
    /* Sweep the disk donut to `pct` (0-100) and count the % label up. */
    donut(pct) {
      const fill = $('#donutFill'), num = $('#donutNum');
      const p = Math.max(0, Math.min(100, pct || 0));
      if (reduce) {
        if (fill) fill.setAttribute('stroke-dasharray', p + ' ' + (100 - p));
        if (num) num.textContent = Math.round(p) + '%';
        return;
      }
      if (fill) g.fromTo(fill, { attr: { 'stroke-dasharray': '0 100' } },
        { attr: { 'stroke-dasharray': p + ' ' + (100 - p) }, duration: 1, ease: 'power2.out' });
      if (num) { const o = { v: 0 };
        g.to(o, { v: p, duration: 1, ease: 'power1.out',
          onUpdate: () => { num.textContent = Math.round(o.v) + '%'; } }); }
    },
```

- [ ] **Step 3: Theme cross-fade pulse**

Add to `AppAnim`:
```javascript
    /* Brief cross-fade pulse on the shell when the theme flips. */
    themeSwitch() {
      if (reduce) return;
      g.fromTo('.app', { opacity: 0.6 }, { opacity: 1, duration: 0.35, ease: 'power2.out' });
    },
```

- [ ] **Step 4: Wire the hooks in script.js**

Find where `AppAnim.intro()` is called and add `window.AppAnim.blobs();` right after it. Find the disk-donut update site (where `#donutFill` `stroke-dasharray` / `#donutNum` are currently set — search `donutFill` / `donutNum` in `script.js`) and route it through `window.AppAnim.donut(usedPct)` instead of setting attributes directly (keep a non-animated fallback for the very first paint if needed). Find the theme-toggle click handler and call `window.AppAnim.themeSwitch();` after the `data-theme` attribute flips. Use the existing `window.AppAnim` reference so the GSAP-missing stub still no-ops safely.

- [ ] **Step 5: Verify**

Reload app. Expected: blobs drift slowly and continuously; on first load and after a scan the donut arc sweeps from 0 and the % counts up; toggling theme gives a quick fade. Then add `?` test: set OS "Reduce Motion" (or temporarily force `reduce = true`) and confirm everything jumps straight to final state with no errors.

- [ ] **Step 6: Commit**

```bash
git add web/anim.js web/script.js
git commit -m "feat: GSAP blob drift, donut sweep, and theme cross-fade"
```

---

### Task 7: Translate static copy (index.html) to English

**Files:**
- Modify: `web/index.html` (all Turkish text: ~45 lines)

**Interfaces:** none (display strings only).

- [ ] **Step 1: Translate all visible strings + aria/placeholder/title attributes**

In `web/index.html`, translate every Turkish string to English. Use these for the recurring UI (matches the design mockup):
- `macOS bakım aracı` → `macOS maintenance`
- Tabs: `Temizlik` → `Cleanup`; `Uygulama Kaldırıcı` → `App Uninstaller`; `Dosyalar` → `Files`
- Sysbar: `Kullanıcı` → `User`; `Boş Alan` → `Free`; `Tahmin` → `Forecast`
- Hero: `Durum · Henüz tarama yapılmadı` → `Status · No scan yet`; `Mac'inizi temizleyin.` → `Reclaim your Mac's space.`; the lead → `Scan caches, logs, temporary files and app leftovers. Nothing is removed until you confirm.`; `temizlenebilir` → `selected to clean`
- Buttons: `Tara` → `Scan`; `Temizle` → `Clean`; dry-run label `Önizleme (silme yok)` → `Preview only`
- Sections: `Kategoriler` → `Categories`; `X kategori` → `X categories`; `Tümünü seç` → `Select all`; `Hiçbirini seçme` → `Clear`; `Sistem Bakımı` → `System maintenance`; `Temizlik dışı onarım araçları` → `Repair tools beyond cleanup`
- Maintenance card names/descriptions + their button labels (`Yenile`→`Rebuild`, `Temizle`→`Flush`/`Clean`, `Boşalt`→`Purge`, `İncelt`→`Thin`), e.g. `Spotlight Dizinini Yeniden Oluştur` → `Rebuild Spotlight Index`, `DNS Önbelleğini Temizle` → `Flush DNS Cache`, `RAM Önbelleğini Boşalt` → `Purge Inactive RAM`, `Bozuk LaunchAgents Temizle` → `Clean Broken LaunchAgents`, `Yerel Snapshot İnceltme` → `Thin Local Snapshots`
- Results: `Temizlik tamamlandı` → `Cleanup complete`
- Uninstaller/Files: `Uygulama ara...` → `Search apps…`; `Taranıyor...` → `Scanning…`; `Temizlenebilir Dosyalar` → `Cleanable Files`; `Önce tarama yapın` → `Scan first`; `Dosya veya yol ara…` → `Search file or path…`; sort options (`Boyut (büyük → küçük)` → `Size (large → small)`, etc.); `Tümünü Seç` → `Select all`; `Seçimi Kaldır` → `Clear`; `Seçilen:` → `Selected:`; `Seçilenleri Temizle` → `Clean selected`; empty state `Henüz tarama yapılmadı. "Tara" düğmesine basın.` → `No scan yet. Press "Scan".`
- Terminal: `Terminal` stays; `İşlem kayıtları` → `Activity log`
- Footer: keep `Glass Cleanup`-style — `macOS sistem temizleme aracı` → `macOS system cleanup tool`
- All `aria-label`s (`Tema değiştir` → `Toggle theme`, `Kapat` → `Dismiss`, `Sistem` → `System`, `Ana Menü` → `Main menu`, `Sıralama` → `Sort`, `İşlem kayıtları` → `Activity log`, etc.) and `placeholder`/`title` attributes.

- [ ] **Step 2: Verify no Turkish remains in index.html**

Run: `grep -nE '[çğışöüÇĞİŞÖÜ]' web/index.html`
Expected: no output (exit 1). Also `grep -nE 'Tara|Temizle|Seç|Kategori|Durum|Dosya|Boyut|Yenile|Boşalt' web/index.html` → no output.

- [ ] **Step 3: Verify in browser**

Reload app. Expected: every visible label/tab/button/section is English; layout intact.

- [ ] **Step 4: Commit**

```bash
git add web/index.html
git commit -m "feat: translate static UI copy to English"
```

---

### Task 8: Translate dynamic copy (script.js) to English

**Files:**
- Modify: `web/script.js` (all Turkish display strings: ~459 lines contain Turkish chars)

**Interfaces:** none (display strings only — do NOT change object keys, ids, function names, or data attributes; only string literals shown to the user).

- [ ] **Step 1: Translate category metadata**

Translate the category `name`/`desc` literals (top of `script.js`, ~lines 15-120) and the developer/extended descriptions (~lines 555+). Examples: `Kullanıcı Cache` → `User Caches`; `Uygulama önbellek dosyaları` → `App cache files`; `Uygulama Kalıntıları` → `App Leftovers`; `Geçici Dosyalar` → `Temporary Files`; `Geliştirici` → `Developer`; `Çöp Kutusu` → `Trash`; `Tarayıcı Cache` → `Browser Cache`; `Mail İndirilenleri` → `Mail Downloads`; `Tanılama Raporları` → `Diagnostic Reports`; `Proje Yapıları` → `Project Builds`. Translate descriptions naturally (technical terms — Xcode, Homebrew, npm, Docker, APFS — stay as-is).

- [ ] **Step 2: Translate status/phase/eyebrow/results/error strings**

Examples: `Sistem bilgileri alınıyor…` → `Reading system info…`; `Tarama yapılıyor…` → `Scanning…`; `Tarama başlatılıyor…` → `Starting scan…`; `Sunucu çalışmıyor · Tarama yapılamadı` → `Server not running · Scan failed`; `Hazır temizlenmeye.` → `Ready to clean.`; the long lead → `Select any of the categories below. All changes are applied only after your confirmation.`; phase button labels (`Tara`/`Taranıyor…`/`Temizle`/`Temizleniyor…`/`Önizle`) → `Scan`/`Scanning…`/`Clean now`/`Cleaning…`/`Preview`; counts like `X / Y seçili` → `X of Y selected`; `açık` → `open`.

- [ ] **Step 3: Translate uninstaller, files-tab, terminal log, and toast strings**

Translate all remaining Turkish in app-uninstaller rendering, files-tab rendering (size/age/total labels), terminal log lines, and any toast/confirm/alert text. Keep byte/number formatting helpers unchanged.

- [ ] **Step 4: Verify no Turkish remains in script.js**

Run: `grep -nE '[çğışöüÇĞİŞÖÜ]' web/script.js`
Expected: no output. Then run the existing test suite to confirm no logic broke:
Run: `cd /Users/burak/Desktop/projects/apple-cleanup && python3 -m pytest -q`
Expected: same pass/fail as before this plan (no new failures).

- [ ] **Step 5: Verify end-to-end in browser**

Reload app. Run scan → categories show English names, sizes count up. Run clean (dry-run + real) → English results banner. Switch tabs → English throughout. Check the terminal log lines are English.

- [ ] **Step 6: Commit**

```bash
git add web/script.js
git commit -m "feat: translate dynamic UI copy to English"
```

---

### Task 9: Final integration pass

**Files:** none expected (fix-ups only)

- [ ] **Step 1: Full walkthrough (dark)**

Run the app. Verify: dark glass renders; blobs drift; intro plays; donut sweeps + counts; scan populates English categories with size count-up; select/clear works; dry-run + real clean show the results banner and update the donut/free space; all 3 tabs, terminal drawer, and the 5 maintenance buttons work and are English + glass.

- [ ] **Step 2: Light theme + reduced motion**

Toggle to light → glass renders correctly, text legible, cross-fade plays. Enable OS Reduce Motion → animations collapse to final state, no console errors.

- [ ] **Step 3: Final copy + token sweep**

Run: `grep -rnE '[çğışöüÇĞİŞÖÜ]' web/index.html web/script.js` → no output.
Confirm no leftover references to removed tokens cause invalid CSS (spot-check console for warnings).

- [ ] **Step 4: Commit any fix-ups**

```bash
git add -A web/
git commit -m "fix: glass redesign integration polish"
```

---

## Self-Review Notes

- **Spec coverage:** §1 tokens/dark/blobs → Task 1; §2 component restyle → Tasks 2-5; §3 GSAP motion → Task 6; §4 language → Tasks 7-8; testing/verification → Task 9. All spec sections mapped.
- **Type consistency:** New `AppAnim` methods `blobs()`, `donut(pct)`, `themeSwitch()` are defined in Task 6 and called via `window.AppAnim.*`, consistent with the existing stub-Proxy fallback in `anim.js`.
- **No backend/test/id changes** per Global Constraints; translation tasks explicitly touch only display string literals.
