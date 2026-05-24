# New UI Migration + Data-Driven Categories Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the old `web/` UI with the refined `newdesign/` UI, and make categories data-driven so adding or removing a cleanup category requires editing only a single array entry in `script.js`.

**Architecture:** Copy `newdesign/` files into `web/`, replacing old HTML/CSS/JS while `server.py` stays untouched. Refactor `script.js` so all category data (name, description, icon, color, default state, tags) lives in a `CATEGORIES` array; a `renderCategories()` function builds the DOM rows at init time. Derived lookup tables (`KEY_BY_INDEX`, `CAT_BY_KEY`, `accentByKey`) are computed from that single array.

**Tech Stack:** Vanilla HTML/CSS/JS, Python HTTP server (`web/server.py`). No build step. No test framework — verification is manual browser testing with the Python server running on port 8080.

---

## File Map

| File | Action | Notes |
|------|--------|-------|
| `web/style.css` | Replace | Verbatim copy from `newdesign/style.css` |
| `web/index.html` | Replace | Copy from `newdesign/index.html`; empty the `<ul id="catList">` |
| `web/script.js` | Replace + refactor | Copy from `newdesign/script.js`; then data-driven refactor |
| `web/server.py` | No change | Already serves the `web/` directory |
| `newdesign/` | Delete | After verifying `web/` works end-to-end |

---

### Task 1: Replace style.css

**Files:**
- Replace: `web/style.css`

- [ ] **Step 1: Copy newdesign/style.css over web/style.css**

```bash
cp newdesign/style.css web/style.css
```

- [ ] **Step 2: Commit**

```bash
git add web/style.css
git commit -m "feat(ui): replace style.css with refined newdesign styles"
```

---

### Task 2: Replace index.html — empty catList

**Files:**
- Replace: `web/index.html`

- [ ] **Step 1: Copy newdesign/index.html over web/index.html**

```bash
cp newdesign/index.html web/index.html
```

- [ ] **Step 2: Empty the catList `<ul>`**

Open `web/index.html`. Find the element:

```html
      <ul class="cat-list" id="catList" role="list">
```

Delete every `<li>` element between its opening and closing `</ul>` tags — all 10 items. Leave the `<ul>` tags themselves. The result:

```html
      <ul class="cat-list" id="catList" role="list">
      </ul>
```

Everything else in the file stays as-is.

- [ ] **Step 3: Commit**

```bash
git add web/index.html
git commit -m "feat(ui): replace index.html with newdesign; catList to be rendered by JS"
```

---

### Task 3: Copy script.js — baseline

**Files:**
- Replace: `web/script.js`

- [ ] **Step 1: Copy newdesign/script.js over web/script.js**

```bash
cp newdesign/script.js web/script.js
```

- [ ] **Step 2: Start the server and verify baseline**

```bash
cd web && python3 server.py
```

Open http://localhost:8080. Expected: page loads, hero/system-bar/terminal/maintenance all render, but **the category list is empty** (catList ul is empty and JS hasn't been made data-driven yet). This is the expected baseline.

- [ ] **Step 3: Commit**

```bash
git add web/script.js
git commit -m "feat(ui): copy newdesign script.js (pre data-driven refactor)"
```

---

### Task 4: Refactor script.js — data-driven categories

**Files:**
- Modify: `web/script.js`

- [ ] **Step 1: Replace CATEGORY_MAP block and its derived lookups**

Find and remove this block near the top of the file (inside the IIFE, under "Constants & data"):

```js
  const CATEGORY_MAP = {
    user_cache:    { index: 1, name: 'Kullanıcı Cache',        color: '#4d8eff' },
    system_cache:  { index: 2, name: 'Sistem Cache',           color: '#6f6ff7' },
    app_leftovers: { index: 3, name: 'Uygulama Kalıntıları',   color: '#a26bf7' },
    logs:          { index: 4, name: 'Loglar',                 color: '#0bb8c9' },
    temp_files:    { index: 5, name: 'Geçici Dosyalar',        color: '#16a34a' },
    developer:     { index: 6, name: 'Geliştirici',            color: '#d97706' },
    trash:         { index: 7, name: 'Çöp Kutusu',             color: '#8b8f99' },
    browser_cache: { index: 8, name: 'Tarayıcı Cache',         color: '#f59e0b' },
    browser_full:  { index: 9, name: 'Tarayıcı Tüm Veri',      color: '#dc2626' },
    ios_backups:   { index: 10, name: 'iOS Yedekleri',         color: '#ef4444' },
  };

  const KEY_BY_INDEX = Object.fromEntries(
    Object.entries(CATEGORY_MAP).map(([k, v]) => [v.index, k])
  );
```

Replace it with:

```js
  const CATEGORIES = [
    {
      key: 'user_cache',    index: 1,  name: 'Kullanıcı Cache',
      desc: 'Uygulama önbellek dosyaları',
      icon: 'i-cache', color: '#4d8eff', defaultChecked: true, danger: false, tags: [],
    },
    {
      key: 'system_cache',  index: 2,  name: 'Sistem Cache',
      desc: 'Sistem seviyesi önbellek',
      icon: 'i-cpu', color: '#6f6ff7', defaultChecked: true, danger: false,
      tags: [{ icon: 'i-lock', label: 'sudo', style: 'amber' }],
    },
    {
      key: 'app_leftovers', index: 3,  name: 'Uygulama Kalıntıları',
      desc: 'Kaldırılmış uygulama artıkları',
      icon: 'i-leftover', color: '#a26bf7', defaultChecked: true, danger: false, tags: [],
    },
    {
      key: 'logs',          index: 4,  name: 'Loglar',
      desc: 'Sistem ve uygulama kayıtları',
      icon: 'i-log', color: '#0bb8c9', defaultChecked: true, danger: false, tags: [],
    },
    {
      key: 'temp_files',    index: 5,  name: 'Geçici Dosyalar',
      desc: 'Geçici ve ara dosyalar',
      icon: 'i-temp', color: '#16a34a', defaultChecked: true, danger: false, tags: [],
    },
    {
      key: 'developer',     index: 6,  name: 'Geliştirici',
      desc: 'Xcode DerivedData ve bozuk linkler',
      icon: 'i-dev', color: '#d97706', defaultChecked: true, danger: false, tags: [],
    },
    {
      key: 'trash',         index: 7,  name: 'Çöp Kutusu',
      desc: 'Çöp kutusundaki dosyalar',
      icon: 'i-trash', color: '#8b8f99', defaultChecked: true, danger: false, tags: [],
    },
    {
      key: 'browser_cache', index: 8,  name: 'Tarayıcı Cache',
      desc: 'Sadece önbellek — çerezler & oturumlar korunur',
      icon: 'i-browser', color: '#f59e0b', defaultChecked: false, danger: false, tags: [],
    },
    {
      key: 'browser_full',  index: 9,  name: 'Tarayıcı Tüm Veri',
      desc: 'Çerezler, geçmiş ve profil verisi',
      icon: 'i-browser-warn', color: '#dc2626', defaultChecked: false, danger: true,
      tags: [{ icon: 'i-warn', label: 'oturumlar kapanır', style: 'red' }],
    },
    {
      key: 'ios_backups',   index: 10, name: 'iOS Yedekleri',
      desc: 'iPhone/iPad MobileSync yedekleri',
      icon: 'i-phone', color: '#ef4444', defaultChecked: false, danger: true,
      tags: [{ icon: 'i-warn', label: 'silmeden önce kontrol', style: 'red' }],
    },
  ];

  const KEY_BY_INDEX = Object.fromEntries(CATEGORIES.map((c) => [c.index, c.key]));
  const CAT_BY_KEY   = Object.fromEntries(CATEGORIES.map((c) => [c.key, c]));
```

- [ ] **Step 2: Replace accentByKey initialization**

Find:

```js
  const accentByKey = {};
  Object.entries(CATEGORY_MAP).forEach(([k, v]) => { accentByKey[k] = v.color; });
```

Replace with:

```js
  const accentByKey = Object.fromEntries(CATEGORIES.map((c) => [c.key, c.color]));
```

- [ ] **Step 3: Update el object — add catList, remove cats**

Find the `el = { ... }` object definition. Make two changes:

1. Delete the line:
```js
    cats:          $$('.cat[data-category]'),
```

2. Add after `categoryCount`:
```js
    categoryCount: $('#categoryCount'),
    catList:       $('#catList'),
```

The tail of the `el` object should now read:

```js
    btnSpotlight:  $('#btnSpotlight'),
    categoryCount: $('#categoryCount'),
    catList:       $('#catList'),
  };
```

- [ ] **Step 4: Add renderCategories() function**

Place this function immediately after the terminal section (right before the `/* ── Utilities ──` comment). `escapeHtml` is a function declaration (hoisted), so calling it here is safe.

```js
  /* ──────────────────────────────────────────────────────────
     Render categories
     ────────────────────────────────────────────────────────── */
  function renderCategories() {
    CATEGORIES.forEach((cat) => {
      const li = document.createElement('li');
      li.className = ['cat', cat.defaultChecked && 'selected', cat.danger && 'cat-danger']
        .filter(Boolean).join(' ');
      li.dataset.category = cat.key;
      li.dataset.index    = String(cat.index);

      const tagsHtml = cat.tags.map((t) =>
        `<span class="tag tag-${t.style}"><svg class="ic"><use href="#${t.icon}"/></svg>${escapeHtml(t.label)}</span>`
      ).join('');

      li.innerHTML = `
        <button class="cat-row" type="button" data-role="row">
          <span class="cat-ic"><svg class="ic"><use href="#${cat.icon}"/></svg></span>
          <span class="cat-meta">
            <span class="cat-name">${escapeHtml(cat.name)}${tagsHtml ? ' ' + tagsHtml : ''}</span>
            <span class="cat-desc">${escapeHtml(cat.desc)}</span>
          </span>
          <span class="cat-bar"><span class="cat-bar-fill"></span></span>
          <span class="cat-size" data-size="${cat.key}">—</span>
          <label class="switch" onclick="event.stopPropagation()">
            <input type="checkbox" ${cat.defaultChecked ? 'checked' : ''} />
            <span class="switch-slider"></span>
          </label>
          <svg class="ic cat-chev"><use href="#i-chev"/></svg>
        </button>
      `;
      el.catList.appendChild(li);
    });

    el.cats = $$('.cat[data-category]');
    if (el.categoryCount) el.categoryCount.textContent = `${CATEGORIES.length} kategori`;
  }
```

- [ ] **Step 5: Replace all remaining CATEGORY_MAP references with CAT_BY_KEY**

Search `web/script.js` for `CATEGORY_MAP`. There should be exactly 3 occurrences. Replace each:

**Occurrence 1** — inside `handleScan`, in the `Object.entries(scan).forEach` callback:
```js
        termLog(`  ${CATEGORY_MAP[key]?.name || key}: ${info.size_human || formatBytes(info.size_bytes)}`);
```
→
```js
        termLog(`  ${CAT_BY_KEY[key]?.name || key}: ${info.size_human || formatBytes(info.size_bytes)}`);
```

**Occurrence 2** — inside `revealHeroResult`, in the legend loop:
```js
      txt.innerHTML = `${CATEGORY_MAP[key]?.name || key} <b>${info.size_human}</b>`;
```
→
```js
      txt.innerHTML = `${escapeHtml(CAT_BY_KEY[key]?.name || key)} <b>${escapeHtml(info.size_human)}</b>`;
```

**Occurrence 3** — inside `handleClean`, the names array:
```js
    const names = selected.map((idx) => CATEGORY_MAP[KEY_BY_INDEX[idx]]?.name || `#${idx}`);
```
→
```js
    const names = selected.map((idx) => CAT_BY_KEY[KEY_BY_INDEX[idx]]?.name || `#${idx}`);
```

- [ ] **Step 6: Remove the inline el.cats.forEach card-interaction block**

Find the inline block that starts with:
```js
  el.cats.forEach((card) => {
    const row = $('[data-role="row"]', card);
    const cb = $('input[type="checkbox"]', card);
```
...and ends a few dozen lines later after the `btnSelectAll` and `btnSelectNone` listeners. **Delete this entire block** — the forEach and the two addEventListener calls for btnSelectAll/btnSelectNone. They will be re-added in the init section in the next step.

Note: the `el.btnScan`, `el.btnClean`, `el.btnSpotlight` addEventListener lines and the keyboard shortcut listener that follow should be **kept** in place.

- [ ] **Step 7: Update the init section at the bottom of the IIFE**

Find the current init block (last lines of the IIFE, after `buildTweaks()`):

```js
  el.term.setAttribute('data-open', 'false');
  termLog('Apple Cleanup başlatıldı.', 'success');
  fetchStatus();
```

Replace it with:

```js
  el.term.setAttribute('data-open', 'false');
  renderCategories();

  // Wire card interactions now that el.cats is populated
  el.cats.forEach((card) => {
    const row = $('[data-role="row"]', card);
    const cb  = $('input[type="checkbox"]', card);

    cb.addEventListener('change', () => {
      card.classList.toggle('selected', cb.checked);
    });

    row.addEventListener('click', (e) => {
      if (e.target.closest('.switch')) return;
      const hasSubs = card.querySelector('.subitems');
      if (hasSubs) {
        const open = card.getAttribute('data-open') === 'true';
        card.setAttribute('data-open', String(!open));
      } else {
        cb.checked = !cb.checked;
        cb.dispatchEvent(new Event('change'));
      }
    });
  });

  el.btnSelectAll.addEventListener('click', () => {
    el.cats.forEach((card) => {
      const cb = $('input[type="checkbox"]', card);
      cb.checked = true;
      card.classList.add('selected');
      $$('.subitems input[type="checkbox"]', card).forEach((s) => (s.checked = true));
    });
    termLog('Tüm kategoriler seçildi.', 'info');
  });

  el.btnSelectNone.addEventListener('click', () => {
    el.cats.forEach((card) => {
      const cb = $('input[type="checkbox"]', card);
      cb.checked = false;
      card.classList.remove('selected');
      $$('.subitems input[type="checkbox"]', card).forEach((s) => (s.checked = false));
    });
    termLog('Tüm seçimler kaldırıldı.', 'info');
  });

  termLog('Apple Cleanup başlatıldı.', 'success');
  fetchStatus();
```

- [ ] **Step 8: Verify in browser**

With the server running at http://localhost:8080, check all of the following:

- All 10 categories appear in the list
- Section header reads "10 kategori"
- `user_cache` through `trash` (7 items) are checked by default
- `browser_cache`, `browser_full`, `ios_backups` are unchecked by default
- `system_cache` has the amber **sudo** tag
- `browser_full` has the red **oturumlar kapanır** tag
- `ios_backups` has the red **silmeden önce kontrol** tag
- Clicking a category row toggles its selection
- "Tümünü seç" and "Hiçbirini seçme" buttons work
- Clicking **Tara** runs the scan and populates sizes in each row
- After scan, stacked bar and big number appear in the hero
- Clicking **Temizle** after a scan completes and shows the results panel
- Theme toggle (sun/moon) switches between light and dark
- Terminal drawer opens and closes
- ⌘S triggers scan, ⌘↩ triggers clean

- [ ] **Step 9: Commit**

```bash
git add web/script.js
git commit -m "feat(ui): make categories data-driven via CATEGORIES array"
```

---

### Task 5: Delete newdesign/ folder

**Files:**
- Delete: `newdesign/`

- [ ] **Step 1: Final confirmation**

Do one last check at http://localhost:8080 — scan, clean, theme toggle all working. The `newdesign/` folder is now redundant.

- [ ] **Step 2: Delete newdesign/**

```bash
rm -rf newdesign/
```

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "chore: remove newdesign/ — migrated to web/"
```
