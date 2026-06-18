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
