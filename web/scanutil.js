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
