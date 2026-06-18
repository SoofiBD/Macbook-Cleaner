/* scanutil.js — pure, DOM-free helpers shared by the dashboard and unit tests.
   Dual export: browser global `window.ScanUtil`, Node `module.exports`. */
(function (root, factory) {
  const api = factory();
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.ScanUtil = api;
})(typeof window !== 'undefined' ? window : globalThis, function () {

  // Categories that expose per-file sub-items AND support per-item cleaning.
  // mail_downloads is intentionally excluded: the server has no per-item clean
  // for it, so a single selection would wipe the whole folder — see review.
  const FILELIST_CATEGORIES = [
    'app_leftovers', 'developer', 'browser_full',
    'ios_backups', 'app_uninstaller', 'project_artifacts',
  ];

  function computeTotalBytes(data) {
    if (data && Number.isFinite(data.total_bytes)) return data.total_bytes;
    const scan = (data && data.scan) || {};
    return Object.values(scan).reduce(
      (sum, info) => sum + (info && info.in_total !== false ? (info.size_bytes || 0) : 0),
      0
    );
  }

  // Map a category risk to a safety badge. Unknown/missing risk falls back to
  // the conservative 'caution' (never the reassuring 'safe') so an unexpected
  // category label can't understate the risk of an item in the file list.
  const SAFETY_BY_RISK = { danger: 'danger', caution: 'caution', safe: 'safe' };
  function safetyForRisk(risk) { return SAFETY_BY_RISK[risk] || 'caution'; }

  function flattenScan(data) {
    const scan = (data && data.scan) || {};
    const rows = [];
    for (const catKey of FILELIST_CATEGORIES) {
      const info = scan[catKey];
      if (!info || !Array.isArray(info.subitems)) continue;
      const safety = safetyForRisk(info.risk);
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

  return {
    FILELIST_CATEGORIES, computeTotalBytes,
    flattenScan, sortRows, filterRows, selectedTotalBytes, buildCleanPayload,
  };
});
