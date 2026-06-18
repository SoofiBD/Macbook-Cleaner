# Fix Scan Hallucination + New Cleanable-Files Tab — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop the dashboard from ever showing fabricated ("hallucinated") files/apps, and add a dedicated "Dosyalar" tab that lists the real cleanable files with per-file sizes, selection, sort/search, and safety flags.

**Architecture:** The hallucination comes from a silent client-side mock fallback in `web/script.js` (`apiFetch` flips `useMock=true` on any failure and returns hardcoded fake data — Slack, zoom.us, Pixelmator Pro, ~50 GB of fake sizes). We remove that fallback so failures surface as real errors. We extract the scan-derived pure logic (total computation, flattening sub-items into a flat file list, sort/filter/selection) into a new dependency-free, dual-export module `web/scanutil.js` that is unit-tested with Node's built-in test runner. A new "Dosyalar" tab renders that flat list and reuses the existing `/api/clean` endpoint and payload shape.

**Tech Stack:** Vanilla JS (browser IIFE + Node `module.exports` dual export), Python stdlib `http.server` (`web/server.py`), Bash (`clean_mac.sh`), GSAP (vendored), Node built-in `node:test`, Python `unittest`.

## Global Constraints

- **No new runtime/build dependencies.** No npm install, no package.json required to run the app. Tests use Node's built-in `node --test` and Python's stdlib `unittest` only.
- **No CDN / network assets.** GSAP and all libraries stay vendored under `web/vendor/`.
- **All user-facing copy is Turkish**, matching existing strings (e.g. "Tarama tamamlandı", "Seçilenleri Temizle", "Sunucu çalışmıyor").
- **Never display fabricated data.** When the server is unreachable or returns an error, show a clear error state and no numbers — never fall back to demo/mock values.
- **Preserve the per-session token security model.** Destructive requests still send `X-Cleanup-Token` from the injected `<meta name="cleanup-token">`. Do not weaken `server.py` validation.
- **Reduced-motion + graceful fallback.** New UI must work if GSAP fails to load (no hard dependency on `window.AppAnim`), and respect `prefers-reduced-motion`.
- **The headline "total cleanable" must not double-count.** Categories overlap (e.g. `app_uninstaller` re-counts apps already in `app_leftovers`); the total must only sum categories flagged `in_total`.
- **Categories that expose per-file sub-items** (the only ones the file list uses): `app_leftovers`, `developer`, `browser_full`, `ios_backups`, `app_uninstaller`, `mail_downloads`, `project_artifacts`.

---

### Task 1: Remove the silent mock fallback

Root cause of the hallucination. After this task, an unreachable/failing server produces a visible error instead of fake apps and inflated sizes.

**Files:**
- Modify: `web/script.js` — `apiFetch` (lines ~351-374), delete `mockApi` (lines ~376-~520), delete `useMock` declaration (line ~170), and audit the page-init calls (`loadStatus`/forecast/`handleScan`) that currently rely on mock on failure.

**Interfaces:**
- Produces: `apiFetch(url, options)` now **rejects** (throws) on any network error or non-success response instead of returning mock data. All callers already wrap it in `try/catch`; this task verifies each catch shows a real error and never fake numbers.

- [ ] **Step 1: Read the current `apiFetch`, `mockApi`, and all callers**

Run: `grep -n "useMock\|mockApi\|apiFetch(" web/script.js`
Read `apiFetch` (≈351-374), `mockApi` (≈376 through its closing `}` — it ends just before `/* Mock API` block finishes; confirm the exact end line, it returns objects for `/api/status`, `/api/forecast`, `/api/scan`, `/api/apps`, `/api/clean`), and the page-init calls that fire on load (search `loadStatus`, `/api/status`, `/api/forecast`).

- [ ] **Step 2: Rewrite `apiFetch` to surface errors (no mock)**

Replace the whole `apiFetch` function with:

```js
  async function apiFetch(url, options = {}) {
    const res = await fetch(url, {
      ...options,
      headers: {
        'Content-Type': 'application/json',
        'X-Cleanup-Token': CLEANUP_TOKEN,
        ...(options.headers || {}),
      },
    });
    if (!res.ok) throw new Error(`Sunucu hatası (HTTP ${res.status})`);
    const data = await res.json();
    if (!data.success && data.error) throw new Error(data.error);
    return data;
  }
```

- [ ] **Step 3: Delete the mock entirely**

Delete the `let useMock = false;` declaration (≈line 170) and the entire `async function mockApi(url, options = {}) { ... }` block including its hardcoded `sizes`, `app_leftovers.subitems`, and `developer.subitems` arrays. Remove any remaining reference to `useMock` or `mockApi` (re-run `grep -n "useMock\|mockApi" web/script.js` — expect zero matches).

- [ ] **Step 4: Make the scan error state visible to the user (not just the terminal)**

In `handleScan`'s `catch` block (≈715-718), ensure a clear user-facing message. Confirm it sets:

```js
    } catch (err) {
      termLog(`Tarama hatası: ${err.message}`, 'error');
      el.hero.setAttribute('data-state', 'idle');
      el.heroEyebrow.textContent = 'Sunucu çalışmıyor · Tarama yapılamadı';
    } finally {
```

(Update the `heroEyebrow` string to the above so it explicitly tells the user the server is not running, rather than a generic "Hata".)

- [ ] **Step 5: Audit page-init calls so a down server degrades gracefully**

For each call that runs on page load (status load, forecast load), confirm it is inside `try/catch` and, on error, shows a dash/placeholder (e.g. leaves `el.sysDiskFree.textContent` as `—` or sets an error label) — it must NOT throw uncaught and must NOT show numbers. If any init call is not wrapped, wrap it so a failure logs `termLog(..., 'error')` and leaves placeholders. Do not invent new UI; reuse existing `—` placeholders already in `index.html`.

- [ ] **Step 6: Manual verification — server OFF**

Run (server intentionally not started):
```bash
python3 -c "print('open web/index.html directly OR load http://localhost:8080 with server stopped')"
```
Use the `run` skill (or open `web/index.html` in a browser). Click **Tara**.
Expected: hero shows "Sunucu çalışmıyor · Tarama yapılamadı"; terminal logs an error; **no** category sizes appear; **no** apps named Slack / zoom.us / Pixelmator Pro / Notion Calendar anywhere. Confirm `grep -n "Slack\|zoom.us\|Pixelmator\|Notion Calendar" web/script.js` returns nothing.

- [ ] **Step 7: Manual verification — server ON**

Run:
```bash
python3 web/server.py &
sleep 1
curl -s http://localhost:8080/ | grep -c "cleanup-token"
```
Load `http://localhost:8080`, click **Tara**. Expected: real categories/sizes load (matching `./clean_mac.sh --scan-json`), no errors. Stop the server (`kill %1`).

- [ ] **Step 8: Run existing tests (no regressions)**

Run: `python3 -m pytest tests/ -q`
Expected: PASS (54 passed, or more).

- [ ] **Step 9: Commit**

```bash
git add web/script.js
git commit -m "fix: remove silent mock fallback that showed fabricated scan data

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Trustworthy total — expose `in_total` and fix client double-count

The backend already excludes overlapping categories from `total_bytes` (`clean_mac.sh:445,2528` — `app_uninstaller` is `in_total=0`). But the client's fallback at `web/script.js:666` (`Object.values(scan).reduce(...)`) sums **all** categories, double-counting overlap when `total_bytes` is absent. We expose `in_total` per category in the scan JSON and compute the total from it in a new tested pure function.

**Files:**
- Create: `web/scanutil.js`
- Create: `tests/test_scanutil.mjs`
- Modify: `clean_mac.sh` — `do_scan_json` per-category emit (≈2544-2548)
- Modify: `tests/test_clean_mac.py` — add a scan-json structure test
- Modify: `web/script.js` — `handleScan` total computation (line ~666)
- Modify: `web/index.html` — load `scanutil.js` before `script.js`

**Interfaces:**
- Produces: `ScanUtil.computeTotalBytes(data)` — returns `data.total_bytes` if a finite number, else sums `size_bytes` of categories where `info.in_total !== false`. Browser global `window.ScanUtil`; Node `module.exports`.
- Produces: scan JSON now includes `"in_total": true|false` on every category object.

- [ ] **Step 1: Write the failing Node test for `computeTotalBytes`**

Create `tests/test_scanutil.mjs`:

```js
import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const ScanUtil = require('../web/scanutil.js');

test('computeTotalBytes prefers numeric total_bytes', () => {
  const data = { total_bytes: 1000, scan: { a: { size_bytes: 999, in_total: true } } };
  assert.equal(ScanUtil.computeTotalBytes(data), 1000);
});

test('computeTotalBytes sums only in_total categories when total_bytes missing', () => {
  const data = { scan: {
    app_leftovers:  { size_bytes: 100, in_total: true },
    app_uninstaller:{ size_bytes: 100, in_total: false },
    developer:      { size_bytes: 50,  in_total: true },
  }};
  assert.equal(ScanUtil.computeTotalBytes(data), 150);
});

test('computeTotalBytes treats missing in_total as included', () => {
  const data = { scan: { a: { size_bytes: 30 }, b: { size_bytes: 20, in_total: true } } };
  assert.equal(ScanUtil.computeTotalBytes(data), 50);
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `node --test tests/test_scanutil.mjs`
Expected: FAIL — cannot find module `../web/scanutil.js`.

- [ ] **Step 3: Create `web/scanutil.js` with `computeTotalBytes`**

```js
/* scanutil.js — pure, DOM-free helpers shared by the dashboard and unit tests.
   Dual export: browser global `window.ScanUtil`, Node `module.exports`. */
(function (root, factory) {
  const api = factory();
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.ScanUtil = api;
})(typeof window !== 'undefined' ? window : globalThis, function () {

  // Categories that expose per-file sub-items (the only ones the file list uses).
  const FILELIST_CATEGORIES = [
    'app_leftovers', 'developer', 'browser_full',
    'ios_backups', 'app_uninstaller', 'mail_downloads', 'project_artifacts',
  ];

  function computeTotalBytes(data) {
    if (data && Number.isFinite(data.total_bytes)) return data.total_bytes;
    const scan = (data && data.scan) || {};
    return Object.values(scan).reduce(
      (sum, info) => sum + (info && info.in_total !== false ? (info.size_bytes || 0) : 0),
      0
    );
  }

  return { FILELIST_CATEGORIES, computeTotalBytes };
});
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `node --test tests/test_scanutil.mjs`
Expected: PASS (3 tests).

- [ ] **Step 5: Add `in_total` to the scan JSON emit**

In `clean_mac.sh`, function `do_scan_json` (≈2538-2548), after the `needs_sudo` line add an `in_total` field. Locate:

```bash
    local needs_sudo="false"
    [ "${CAT_NEEDS_SUDO[$i]}" -eq 1 ] && needs_sudo="true"
```
and insert below it:
```bash
    local in_total="false"
    [ "${CAT_IN_TOTAL[$i]}" -eq 1 ] && in_total="true"
```
Then change the emitted block from:
```bash
    echo "      \"needs_sudo\": $needs_sudo,"
    echo "      \"risk\": \"${CAT_RISKS[$i]}\""
```
to:
```bash
    echo "      \"needs_sudo\": $needs_sudo,"
    echo "      \"in_total\": $in_total,"
    echo "      \"risk\": \"${CAT_RISKS[$i]}\""
```

- [ ] **Step 6: Write the failing Python test for scan-json structure**

Add to `tests/test_clean_mac.py` (new test class at end of file):

```python
import json
import subprocess

class TestScanJsonStructure(unittest.TestCase):
    def _scan(self):
        repo = os.path.join(os.path.dirname(__file__), '..')
        out = subprocess.run(
            ['bash', os.path.join(repo, 'clean_mac.sh'), '--scan-json'],
            capture_output=True, text=True, timeout=180,
        )
        self.assertEqual(out.returncode, 0, out.stderr)
        return json.loads(out.stdout)

    def test_every_category_has_in_total_flag(self):
        data = self._scan()
        for key, info in data['scan'].items():
            self.assertIn('in_total', info, f'{key} missing in_total')
            self.assertIsInstance(info['in_total'], bool)

    def test_app_uninstaller_excluded_from_total(self):
        data = self._scan()
        self.assertFalse(data['scan']['app_uninstaller']['in_total'])

    def test_total_bytes_equals_in_total_sum(self):
        data = self._scan()
        expected = sum(i.get('size_bytes', 0) for i in data['scan'].values()
                       if i.get('in_total'))
        self.assertEqual(data['total_bytes'], expected)
```

Note: ensure `import os` already present at top of the file (it is). Add `import json`, `import subprocess` if missing.

- [ ] **Step 7: Run the Python test to verify it passes**

Run: `python3 -m pytest tests/test_clean_mac.py::TestScanJsonStructure -q`
Expected: PASS (3 tests). (This runs a real scan; allow up to 180s.)

- [ ] **Step 8: Wire the client to use `computeTotalBytes` and load the module**

In `web/index.html`, add before the existing `<script src="script.js">` (and before `anim.js` is fine too — `scanutil.js` has no dependencies):
```html
    <script src="scanutil.js"></script>
```
In `web/script.js` `handleScan` (line ~666), replace:
```js
      const totalBytes = data.total_bytes || Object.values(scan).reduce((a, s) => a + (s.size_bytes || 0), 0);
```
with:
```js
      const totalBytes = window.ScanUtil.computeTotalBytes(data);
```

- [ ] **Step 9: Manual verification of the total in the browser**

Start the server, load the dashboard, click **Tara**. Expected: headline total equals `total_human` from `./clean_mac.sh --scan-json` (the `app_uninstaller` 9.1 GB is NOT added on top of `app_leftovers`). Cross-check:
```bash
./clean_mac.sh --scan-json | python3 -c "import json,sys;d=json.load(sys.stdin);print('total_human=',d['total_human'])"
```

- [ ] **Step 10: Commit**

```bash
git add web/scanutil.js tests/test_scanutil.mjs clean_mac.sh tests/test_clean_mac.py web/script.js web/index.html
git commit -m "fix: expose in_total per category and compute headline total without double-counting

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Pure file-list logic in `scanutil.js` (flatten / sort / filter / select / payload)

DOM-free functions the new tab will render. All TDD-tested with `node:test`. No UI yet.

**Files:**
- Modify: `web/scanutil.js`
- Modify: `tests/test_scanutil.mjs`

**Interfaces:**
- Consumes: `FILELIST_CATEGORIES`, `computeTotalBytes` (Task 2).
- Produces, all on `ScanUtil`:
  - `flattenScan(data)` → array of row objects:
    `{ rowId, catKey, catName, id, name, sizeBytes, sizeHuman, ageDays, path, risk, isOrphaned, safety }`
    where `safety` is `'danger' | 'caution' | 'safe'`, `rowId = catKey + '::' + id` (stable, unique).
  - `sortRows(rows, key, dir)` — `key ∈ {'size','age','name'}`, `dir ∈ {'asc','desc'}`; returns a new sorted array (stable; nulls sort last).
  - `filterRows(rows, query)` — case-insensitive match on `name`, `catName`, or `path`; empty query returns all.
  - `selectedTotalBytes(rows, selectedRowIds)` — sum of `sizeBytes` for rows whose `rowId ∈ selectedRowIds` (a `Set` or array).
  - `buildCleanPayload(selectedRows, indexByKey)` → `{ categories:[...uniqueIndices], app_leftovers_selected:[ids], browser_full_selected:[ids], developer_selected:[ids], ios_backups_selected:[ids], app_uninstaller_selected:[ids], project_artifacts_selected:[ids], mail_downloads_selected:[ids] }`. `indexByKey` maps catKey→numeric category index. Only categories present among `selectedRows` appear in `categories`. Each `<cat>_selected` lists the selected sub-`id`s for that cat.

- [ ] **Step 1: Write failing tests for the pure functions**

Append to `tests/test_scanutil.mjs`:

```js
const SAMPLE = {
  total_bytes: 500,
  scan: {
    app_leftovers: { size_bytes: 300, in_total: true, risk: 'caution', subitems: [
      { id: 'Claude', name: 'Claude', size_bytes: 200, size_human: '200 B', path: '/u/Claude', is_orphaned: false },
      { id: 'OldApp', name: 'OldApp', size_bytes: 100, size_human: '100 B', path: '/u/OldApp', is_orphaned: true },
    ]},
    browser_full: { size_bytes: 50, in_total: true, risk: 'danger', subitems: [
      { id: 'chrome', name: 'Google Chrome', size_bytes: 50, size_human: '50 B', age_days: 5, is_orphaned: false },
    ]},
    user_cache: { size_bytes: 150, in_total: true },           // no subitems -> ignored
    app_uninstaller: { size_bytes: 300, in_total: false, subitems: [
      { id: 'Claude', name: 'Claude', size_bytes: 200, size_human: '200 B' },
    ]},
  },
};

test('flattenScan only includes categories with subitems', () => {
  const rows = ScanUtil.flattenScan(SAMPLE);
  const cats = new Set(rows.map(r => r.catKey));
  assert.ok(!cats.has('user_cache'));
  assert.ok(cats.has('app_leftovers'));
  assert.equal(rows.length, 4); // 2 + 1 + 1
});

test('flattenScan rowId is unique and stable', () => {
  const rows = ScanUtil.flattenScan(SAMPLE);
  assert.equal(new Set(rows.map(r => r.rowId)).size, rows.length);
  assert.ok(rows.some(r => r.rowId === 'app_leftovers::Claude'));
});

test('flattenScan maps safety from risk', () => {
  const rows = ScanUtil.flattenScan(SAMPLE);
  assert.equal(rows.find(r => r.rowId === 'browser_full::chrome').safety, 'danger');
  assert.equal(rows.find(r => r.rowId === 'app_leftovers::Claude').safety, 'caution');
});

test('sortRows by size desc', () => {
  const rows = ScanUtil.sortRows(ScanUtil.flattenScan(SAMPLE), 'size', 'desc');
  assert.equal(rows[0].sizeBytes, 200);
  assert.equal(rows[rows.length - 1].sizeBytes, 50);
});

test('filterRows matches name and path case-insensitively', () => {
  const rows = ScanUtil.flattenScan(SAMPLE);
  assert.equal(ScanUtil.filterRows(rows, 'claude').length, 2); // app_leftovers + app_uninstaller
  assert.equal(ScanUtil.filterRows(rows, '/u/OldApp').length, 1);
  assert.equal(ScanUtil.filterRows(rows, '').length, rows.length);
});

test('selectedTotalBytes sums only selected rowIds', () => {
  const rows = ScanUtil.flattenScan(SAMPLE);
  const sel = new Set(['app_leftovers::Claude', 'browser_full::chrome']);
  assert.equal(ScanUtil.selectedTotalBytes(rows, sel), 250);
});

test('buildCleanPayload groups ids by category with indices', () => {
  const rows = ScanUtil.flattenScan(SAMPLE).filter(
    r => r.rowId === 'app_leftovers::OldApp' || r.rowId === 'browser_full::chrome'
  );
  const indexByKey = { app_leftovers: 3, browser_full: 9 };
  const p = ScanUtil.buildCleanPayload(rows, indexByKey);
  assert.deepEqual(p.categories.sort(), [3, 9]);
  assert.deepEqual(p.app_leftovers_selected, ['OldApp']);
  assert.deepEqual(p.browser_full_selected, ['chrome']);
  assert.deepEqual(p.developer_selected, []);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `node --test tests/test_scanutil.mjs`
Expected: FAIL — `ScanUtil.flattenScan is not a function`.

- [ ] **Step 3: Implement the pure functions**

In `web/scanutil.js`, inside the factory (before the `return`), add:

```js
  const SAFETY_BY_RISK = { danger: 'danger', caution: 'caution' };

  function flattenScan(data) {
    const scan = (data && data.scan) || {};
    const rows = [];
    for (const catKey of FILELIST_CATEGORIES) {
      const info = scan[catKey];
      if (!info || !Array.isArray(info.subitems)) continue;
      const safety = SAFETY_BY_RISK[info.risk] || 'safe';
      for (const sub of info.subitems) {
        rows.push({
          rowId: catKey + '::' + sub.id,
          catKey,
          catName: catKey,
          id: sub.id,
          name: sub.name || sub.id,
          sizeBytes: Number.isFinite(sub.size_bytes) ? sub.size_bytes : null,
          sizeHuman: sub.size_human || '',
          ageDays: Number.isFinite(sub.age_days) ? sub.age_days
                   : (Number.isFinite(sub.days_since) ? sub.days_since : null),
          path: sub.path || '',
          risk: info.risk || '',
          isOrphaned: !!sub.is_orphaned,
          safety,
        });
      }
    }
    return rows;
  }

  function sortRows(rows, key, dir) {
    const mult = dir === 'asc' ? 1 : -1;
    const pick = {
      size: (r) => r.sizeBytes,
      age:  (r) => r.ageDays,
      name: (r) => (r.name || '').toLowerCase(),
    }[key] || ((r) => r.sizeBytes);
    return rows
      .map((r, i) => [r, i])
      .sort(([a, ai], [b, bi]) => {
        const va = pick(a), vb = pick(b);
        const na = va == null, nb = vb == null;
        if (na && nb) return ai - bi;       // stable
        if (na) return 1;                    // nulls last regardless of dir
        if (nb) return -1;
        if (va < vb) return -1 * mult;
        if (va > vb) return 1 * mult;
        return ai - bi;                      // stable tiebreak
      })
      .map(([r]) => r);
  }

  function filterRows(rows, query) {
    const q = (query || '').trim().toLowerCase();
    if (!q) return rows.slice();
    return rows.filter((r) =>
      (r.name || '').toLowerCase().includes(q) ||
      (r.catName || '').toLowerCase().includes(q) ||
      (r.path || '').toLowerCase().includes(q)
    );
  }

  function selectedTotalBytes(rows, selectedRowIds) {
    const set = selectedRowIds instanceof Set ? selectedRowIds : new Set(selectedRowIds);
    return rows.reduce(
      (sum, r) => sum + (set.has(r.rowId) ? (r.sizeBytes || 0) : 0), 0);
  }

  function buildCleanPayload(selectedRows, indexByKey) {
    const payload = {
      categories: [],
      app_leftovers_selected: [],
      browser_full_selected: [],
      developer_selected: [],
      ios_backups_selected: [],
      app_uninstaller_selected: [],
      project_artifacts_selected: [],
      mail_downloads_selected: [],
    };
    const idxSet = new Set();
    for (const r of selectedRows) {
      const bucket = r.catKey + '_selected';
      if (Array.isArray(payload[bucket])) payload[bucket].push(r.id);
      const idx = indexByKey[r.catKey];
      if (idx != null) idxSet.add(idx);
    }
    payload.categories = Array.from(idxSet);
    return payload;
  }
```

Update the `return` line to include them:
```js
  return {
    FILELIST_CATEGORIES, computeTotalBytes,
    flattenScan, sortRows, filterRows, selectedTotalBytes, buildCleanPayload,
  };
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `node --test tests/test_scanutil.mjs`
Expected: PASS (all tests from Tasks 2 and 3).

- [ ] **Step 5: Commit**

```bash
git add web/scanutil.js tests/test_scanutil.mjs
git commit -m "feat: add pure file-list helpers (flatten/sort/filter/select/payload) with tests

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: "Dosyalar" tab markup + styles (static)

Add the third tab and its (empty) content panel + CSS. No behavior yet — wiring is Task 5.

**Files:**
- Modify: `web/index.html` — add tab button (after `#tab-uninstaller`, ≈line 173) and a new tab content section (after the uninstaller tab content, ≈after line 351 block).
- Modify: `web/style.css` — styles for `.filelist-*` rows, toolbar, safety badges, running-total bar.

**Interfaces:**
- Produces these DOM ids/classes consumed by Task 5: `#tab-files`, `#filesTabContent`, `#filesSearch`, `#filesSort` (a `<select>`), `#filesSelectAll`, `#filesSelectNone`, `#filesList` (a `<ul>`), `#filesSelectedTotal`, `#filesCount`, `#btnCleanSelected`, `#filesEmpty`.

- [ ] **Step 1: Read the existing tab + uninstaller markup for pattern**

Read `web/index.html` ≈168-176 (the `<nav class="nav-tabs">`) and the uninstaller tab content (≈351 onward: `#uninstallerTabContent`, `#appsSearch`, `#appsList`, `#appsCount`). Match class names and structure.

- [ ] **Step 2: Add the tab button**

After the `#tab-uninstaller` button (≈line 173-176 block, before `</nav>`), add:
```html
      <button class="tab-btn" role="tab" aria-selected="false" aria-controls="filesTabContent" id="tab-files" type="button">
        <span>Dosyalar</span>
      </button>
```

- [ ] **Step 3: Add the tab content panel**

After the closing of `#uninstallerTabContent` section, add:
```html
    <!-- ═══ Cleanable Files Tab Content ═══ -->
    <section id="filesTabContent" class="tab-content" role="tabpanel" aria-labelledby="tab-files" hidden>
      <div class="files-head">
        <div>
          <h2 class="section-title">Temizlenebilir Dosyalar</h2>
          <span class="section-sub" id="filesCount">Önce tarama yapın</span>
        </div>
        <div class="files-toolbar">
          <input type="search" id="filesSearch" class="files-search" placeholder="Dosya veya yol ara…" autocomplete="off" />
          <select id="filesSort" class="files-sort" aria-label="Sıralama">
            <option value="size:desc">Boyut (büyük → küçük)</option>
            <option value="size:asc">Boyut (küçük → büyük)</option>
            <option value="age:desc">Yaş (eski → yeni)</option>
            <option value="name:asc">Ad (A → Z)</option>
          </select>
          <button class="btn btn-sm" id="filesSelectAll" type="button">Tümünü Seç</button>
          <button class="btn btn-sm" id="filesSelectNone" type="button">Seçimi Kaldır</button>
        </div>
      </div>

      <ul id="filesList" class="files-list" aria-live="polite"></ul>
      <div id="filesEmpty" class="files-empty" hidden>Henüz tarama yapılmadı. "Tara" düğmesine basın.</div>

      <div class="files-footer">
        <span class="files-total-label">Seçilen: <b id="filesSelectedTotal">0 B</b></span>
        <button class="btn btn-accent" id="btnCleanSelected" type="button" disabled>Seçilenleri Temizle</button>
      </div>
    </section>
```

- [ ] **Step 4: Add CSS**

Append to `web/style.css` (reuse existing custom properties like `--accent`, `--border`, surface vars — check the top of `style.css` for the actual variable names and match them; the block below uses common ones, adjust to the file's real tokens):
```css
/* ── Cleanable Files tab ───────────────────────────────────── */
.files-head { display: flex; justify-content: space-between; align-items: flex-start; gap: 1rem; flex-wrap: wrap; margin-bottom: 1rem; }
.files-toolbar { display: flex; gap: .5rem; align-items: center; flex-wrap: wrap; }
.files-search { padding: .5rem .75rem; border: 1px solid var(--border, #d9d9de); border-radius: 8px; min-width: 200px; }
.files-sort { padding: .5rem; border: 1px solid var(--border, #d9d9de); border-radius: 8px; }
.files-list { list-style: none; margin: 0; padding: 0; display: flex; flex-direction: column; gap: 2px; }
.file-row { display: grid; grid-template-columns: auto 1fr auto auto; align-items: center; gap: .75rem; padding: .6rem .75rem; border-radius: 8px; }
.file-row:hover { background: var(--surface-2, rgba(0,0,0,.03)); }
.file-main { display: flex; flex-direction: column; min-width: 0; }
.file-name { font-weight: 600; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.file-path { font-size: .78rem; opacity: .6; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.file-size { font-variant-numeric: tabular-nums; font-weight: 600; }
.file-badge { font-size: .72rem; padding: .1rem .45rem; border-radius: 999px; white-space: nowrap; }
.file-badge.safety-danger { background: #fde2e2; color: #b3261e; }
.file-badge.safety-caution { background: #fef3d8; color: #9a6700; }
.file-badge.safety-safe { background: #e3f1e6; color: #1c7a3d; }
.files-footer { display: flex; justify-content: space-between; align-items: center; gap: 1rem; margin-top: 1rem; padding-top: 1rem; border-top: 1px solid var(--border, #d9d9de); }
.files-empty { padding: 2rem; text-align: center; opacity: .6; }
@media (prefers-reduced-motion: no-preference) { .file-row { transition: background .15s ease; } }
```

- [ ] **Step 5: Verify markup loads (no JS yet)**

Start the server, open the dashboard, click the **Dosyalar** tab button.
Expected: tab is clickable in the nav. (It won't switch yet — Task 5 — but the button and panel exist in the DOM. Confirm via devtools that `#filesTabContent` exists.)
Run: `grep -c "filesTabContent\|tab-files\|btnCleanSelected" web/index.html` → expect ≥ 3.

- [ ] **Step 6: Commit**

```bash
git add web/index.html web/style.css
git commit -m "feat: add Dosyalar (cleanable files) tab markup and styles

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: Wire the Dosyalar tab — render rows, selection, running total, sort/search

Make the tab functional: switch to it, render real `scanData` rows via `ScanUtil`, per-row checkboxes with a running selected total, sort and search.

**Files:**
- Modify: `web/script.js` — extend `showTab` (≈1265-1282) to handle `'files'`; add `renderFileList`, selection state, sort/search handlers; reference `scanData`.

**Interfaces:**
- Consumes: `ScanUtil.flattenScan/sortRows/filterRows/selectedTotalBytes` (Task 3), module-level `scanData`, `KEY_BY_INDEX`/`CAT_BY_KEY`/`CATEGORIES` (for names/indices), `formatBytes`, `escapeHtml`, `escapeAttr`.
- Produces: `renderFileList()` (reads `scanData`, current sort, current query, current selection and repaints `#filesList`); `getFilesCleanPayload()` used by Task 6.

- [ ] **Step 1: Add Dosyalar branch to `showTab`**

Refactor `showTab` to a 3-way. Replace the existing two-branch body so all three tabs toggle correctly. Read current `showTab` first, then implement a version that:
- sets `aria-selected` and `.active` on whichever of `#tab-cleanup`/`#tab-uninstaller`/`#tab-files` matches,
- shows the matching content (`cleanupTabContent` / `uninstallerTabContent` / `filesTabContent`), hides the others,
- calls `loadApplications()` only for `'uninstaller'`, and `renderFileList()` for `'files'`.

```js
  const tabFiles = $('#tab-files');
  const filesTabContent = $('#filesTabContent');

  function showTab(tabId) {
    const map = {
      cleanup:     [tabCleanup, cleanupTabContent],
      uninstaller: [tabUninstaller, uninstallerTabContent],
      files:       [tabFiles, filesTabContent],
    };
    Object.entries(map).forEach(([id, [btn, content]]) => {
      const active = id === tabId;
      btn.classList.toggle('active', active);
      btn.setAttribute('aria-selected', active ? 'true' : 'false');
      content.hidden = !active;
    });
    if (tabId === 'uninstaller') loadApplications();
    if (tabId === 'files') renderFileList();
  }

  tabFiles.addEventListener('click', () => showTab('files'));
```
(Keep the existing `tabCleanup`/`tabUninstaller` click listeners.)

- [ ] **Step 2: Add file-list state + render function**

Add near the other tab code:
```js
  const filesSearch = $('#filesSearch');
  const filesSort = $('#filesSort');
  const filesList = $('#filesList');
  const filesEmpty = $('#filesEmpty');
  const filesCountEl = $('#filesCount');
  const filesSelectedTotalEl = $('#filesSelectedTotal');
  const btnCleanSelected = $('#btnCleanSelected');

  const filesSelected = new Set();   // rowIds
  let filesQuery = '';

  function currentFileRows() {
    const all = window.ScanUtil.flattenScan(scanData || {});
    // attach human category names
    all.forEach((r) => { r.catName = CAT_BY_KEY[r.catKey]?.name || r.catKey; });
    const [key, dir] = (filesSort?.value || 'size:desc').split(':');
    return window.ScanUtil.sortRows(
      window.ScanUtil.filterRows(all, filesQuery), key, dir);
  }

  function updateFilesTotal() {
    const allRows = window.ScanUtil.flattenScan(scanData || {});
    const total = window.ScanUtil.selectedTotalBytes(allRows, filesSelected);
    filesSelectedTotalEl.textContent = formatBytes(total);
    btnCleanSelected.disabled = filesSelected.size === 0;
  }

  function renderFileList() {
    if (!scanData || !scanData.scan) {
      filesList.innerHTML = '';
      filesEmpty.hidden = false;
      filesCountEl.textContent = 'Önce tarama yapın';
      updateFilesTotal();
      return;
    }
    const rows = currentFileRows();
    filesEmpty.hidden = rows.length > 0;
    filesCountEl.textContent = `${rows.length} dosya`;
    filesList.innerHTML = '';
    const badgeLabel = { danger: 'riskli', caution: 'dikkat', safe: 'güvenli' };
    rows.forEach((r) => {
      const li = document.createElement('li');
      li.className = 'file-row';
      const checked = filesSelected.has(r.rowId) ? 'checked' : '';
      const ageStr = r.ageDays != null ? ` · ${r.ageDays}g` : '';
      li.innerHTML = `
        <input type="checkbox" data-row-id="${escapeAttr(r.rowId)}" ${checked}>
        <span class="file-main">
          <span class="file-name" title="${escapeAttr(r.name)}">${escapeHtml(r.name)}</span>
          <span class="file-path">${escapeHtml(r.catName)}${ageStr}${r.path ? ' · ' + escapeHtml(r.path) : ''}</span>
        </span>
        <span class="file-badge safety-${r.safety}">${badgeLabel[r.safety]}</span>
        <span class="file-size">${escapeHtml(r.sizeHuman || formatBytes(r.sizeBytes || 0))}</span>
      `;
      filesList.appendChild(li);
    });
    filesList.querySelectorAll('input[type="checkbox"]').forEach((cb) => {
      cb.addEventListener('change', () => {
        const id = cb.dataset.rowId;
        if (cb.checked) filesSelected.add(id); else filesSelected.delete(id);
        updateFilesTotal();
      });
    });
    updateFilesTotal();
  }
```

- [ ] **Step 3: Wire toolbar controls**

```js
  if (filesSearch) filesSearch.addEventListener('input', () => {
    filesQuery = filesSearch.value; renderFileList();
  });
  if (filesSort) filesSort.addEventListener('change', renderFileList);
  if ($('#filesSelectAll')) $('#filesSelectAll').addEventListener('click', () => {
    currentFileRows().forEach((r) => filesSelected.add(r.rowId));
    renderFileList();
  });
  if ($('#filesSelectNone')) $('#filesSelectNone').addEventListener('click', () => {
    filesSelected.clear(); renderFileList();
  });
```

- [ ] **Step 4: Clear file selection on each fresh scan**

In `handleScan`, after `scanData = data;` (line ~658), add:
```js
      filesSelected.clear();
```
(So a new scan doesn't keep stale selections from the previous scan. Guard: only if `filesSelected` is in scope — it is, defined at module level in the same IIFE. If ordering causes a temporal-dead-zone issue, move the `const filesSelected = new Set();` declaration up near the other module-level `let scanData` declarations.)

- [ ] **Step 5: Manual verification**

Start server, load dashboard, click **Tara**, then the **Dosyalar** tab.
Expected:
- Real files appear (e.g. `Claude` under "Uygulama Kalıntıları", browser entries under "Tarayıcı Tüm Veri"), each with a real size and a safety badge.
- Typing in search filters live; changing the sort reorders.
- Ticking rows updates "Seçilen: X" and enables **Seçilenleri Temizle**.
- "Tümünü Seç" / "Seçimi Kaldır" work.
- No fake apps (Slack/zoom.us/etc.) anywhere.

- [ ] **Step 6: Commit**

```bash
git add web/script.js
git commit -m "feat: render and wire the Dosyalar tab (rows, selection, total, sort, search)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: Clean selected files from the Dosyalar tab

Wire **Seçilenleri Temizle** to the existing `/api/clean` endpoint using the shared payload builder, with confirmation for risky items, then refresh.

**Files:**
- Modify: `web/script.js` — add `handleCleanSelectedFiles`, wire `#btnCleanSelected`, reuse existing result rendering.

**Interfaces:**
- Consumes: `ScanUtil.buildCleanPayload` (Task 3), `KEY_BY_INDEX`/`CATEGORIES` for `indexByKey`, `apiFetch`, `scanData`, `filesSelected`, existing result-panel elements (`el.resultsPanel`, `el.resultsTitle`, etc. from `handleClean`), `el.dryRunToggle`.

- [ ] **Step 1: Build `indexByKey` and the handler**

Add:
```js
  const INDEX_BY_KEY = Object.fromEntries(CATEGORIES.map((c) => [c.key, c.index]));

  async function handleCleanSelectedFiles() {
    if (isLoading || filesSelected.size === 0) return;
    const rows = window.ScanUtil.flattenScan(scanData || {})
      .filter((r) => filesSelected.has(r.rowId));

    const dangerRows = rows.filter((r) => r.safety === 'danger');
    const confirmed = confirm(
      `${rows.length} öğe temizlenecek (${filesSelectedTotalEl.textContent}). Devam edilsin mi?`);
    if (!confirmed) { termLog('Temizlik iptal edildi.', 'info'); return; }
    if (dangerRows.length > 0) {
      const ok = confirm(
        `RİSKLİ öğeler seçildi (${dangerRows.length}). Bu veriler kalıcı olarak silinir ve geri alınamaz. Devam edilsin mi?`);
      if (!ok) { termLog('Riskli öğeler onaylanmadı, temizlik iptal edildi.', 'info'); return; }
    }

    isLoading = true;
    setLoading(btnCleanSelected, true);
    termLog(`Seçilen dosyalar temizleniyor (${rows.length})…`, 'info');
    try {
      const dryRun = !!(el.dryRunToggle && el.dryRunToggle.checked);
      const payload = window.ScanUtil.buildCleanPayload(rows, INDEX_BY_KEY);
      payload.dry_run = dryRun;
      const data = await apiFetch('/api/clean', {
        method: 'POST', body: JSON.stringify(payload),
      });
      el.resultsPanel.hidden = false;
      el.resultsPanel.classList.remove('error');
      el.resultsTitle.textContent = data.dry_run
        ? 'Önizleme (hiçbir şey silinmedi)' : 'Temizlik tamamlandı';
      el.resultsFreed.textContent = data.dry_run
        ? (data.estimated_human || formatBytes(data.estimated_bytes || 0))
        : (data.freed_human || formatBytes(data.freed_bytes || 0));
      if (data.disk_free) el.sysDiskFree.textContent = data.disk_free;
      termLog(`Temizlik tamamlandı — ${el.resultsFreed.textContent}`, 'success');
      if (!data.dry_run) { filesSelected.clear(); }
      renderFileList();
    } catch (err) {
      termLog(`Temizlik hatası: ${err.message}`, 'error');
    } finally {
      setLoading(btnCleanSelected, false);
      isLoading = false;
    }
  }

  if (btnCleanSelected) btnCleanSelected.addEventListener('click', handleCleanSelectedFiles);
```

Note on `setLoading`: confirm it tolerates being called with `btnCleanSelected` (same pattern as `el.btnClean`). If `setLoading` requires a specific structure (e.g. a `.btn-text`/`.spinner` child), the markup in Task 4 must include them; check `setLoading`'s implementation and, if needed, add `<span class="spinner" aria-hidden="true"></span><span class="btn-text">Seçilenleri Temizle</span>` inside `#btnCleanSelected` in `index.html` instead of bare text.

- [ ] **Step 2: Manual verification — dry run**

Start server. Enable the **Önizleme** (dry-run) toggle. Scan, go to **Dosyalar**, select a couple of low-risk items (e.g. a dev cache), click **Seçilenleri Temizle**, confirm.
Expected: results panel shows "Önizleme (hiçbir şey silinmedi)" with an estimated size; nothing is actually deleted (verify the file still exists on disk).

- [ ] **Step 3: Manual verification — payload shape**

Add a temporary `console.log(payload)` (or inspect the Network tab) and confirm the POST body matches the server's expected fields: `categories` (numeric indices), and `<cat>_selected` arrays of sub-ids. Cross-check against `web/server.py` `_handle_clean` (≈539) to ensure field names line up (`app_leftovers_selected`, `developer_selected`, `browser_full_selected`, `ios_backups_selected`, `app_uninstaller_selected`, `project_artifacts_selected`). Remove the temporary log.

- [ ] **Step 4: Run all tests**

Run:
```bash
node --test tests/test_scanutil.mjs && python3 -m pytest tests/ -q
```
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add web/script.js web/index.html
git commit -m "feat: clean selected files from the Dosyalar tab via /api/clean

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:**
- "Hallucinated non-existent files/apps" → Task 1 removes the silent mock fallback (the source of Slack/zoom.us/Pixelmator fakes).
- "Size increases on re-scan" → Task 1 (mock totals were larger and triggered on the session flip) + Task 2 (`computeTotalBytes` and `in_total` ensure a stable, non-double-counted total).
- "Fix the total double-count" (user-approved) → Task 2.
- "New UI list of cleanable files" → Tasks 3-6: dedicated "Dosyalar" tab, per-file rows + sizes (3,4,5), checkbox selection + running total (5), sort & search (5), safety flags (3 `safety`, 4 CSS, 5 render), cleaning from the list (6).
- "Use existing per-item data only" → `FILELIST_CATEGORIES` limits to categories that already emit sub-items; no `clean_mac.sh` scan-depth changes.

**Placeholder scan:** No "TBD"/"add error handling"-style placeholders; all code steps contain full code. Two steps intentionally say "confirm the exact end line / confirm `setLoading` shape" — these are verification instructions with explicit fallbacks, not missing code.

**Type consistency:** `rowId` format `catKey::id` is used identically in flatten, selection, and tests. `buildCleanPayload` field names match `handleClean`'s payload and `server.py` `_handle_clean`. `computeTotalBytes`/`flattenScan`/`sortRows`/`filterRows`/`selectedTotalBytes`/`buildCleanPayload` signatures match between the module, the tests, and the callers.

**Known cross-task dependency:** `web/index.html` must load `scanutil.js` before `script.js` (added in Task 2 Step 8); Tasks 5-6 depend on `window.ScanUtil` existing.
