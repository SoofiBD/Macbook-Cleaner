# Task 6 Report — Clean selected files from the Dosyalar tab

## Changes (web/script.js)
- Added INDEX_BY_KEY = {catKey: numeric index} from CATEGORIES.
- Added handleCleanSelectedFiles(): builds the selected row list from scanData via ScanUtil.flattenScan filtered by filesSelected; confirm() summary (count + selected total); extra confirm() if any safety==='danger' rows; builds payload via ScanUtil.buildCleanPayload(rows, INDEX_BY_KEY), sets dry_run from el.dryRunToggle; POSTs /api/clean via apiFetch; renders into existing results panel (resultsTitle/resultsFreed), updates sysDiskFree; clears filesSelected on a real (non-dry-run) clean; re-renders. try/catch surfaces "Temizlik hatası". setLoading(btnCleanSelected) guards.
- Wired #btnCleanSelected click -> handleCleanSelectedFiles.

## Verification
- node --check web/script.js -> OK.
- buildCleanPayload on real rows -> {categories:[3,6,9], app_leftovers_selected:["Claude"], developer_selected:["npm_cache"], browser_full_selected:["edge"], others []} — field names match server _handle_clean (server.py:545,565,573...).
- End-to-end dry-run via live server: POST /api/clean {categories:[6],developer_selected:["npm_cache"],dry_run:true} -> dry_run=true, estimated_human=70.0 MB, freed_bytes=0, success=true; npm cache dir intact afterward (nothing deleted).
- node --test (12 pass), pytest (56 passed) green.

## Commit
- c0cc830 (BASE 060b465)

## Notes
- Reuses the existing results panel + setLoading; no new endpoints. Selection opt-in; danger items require a second explicit confirm.
