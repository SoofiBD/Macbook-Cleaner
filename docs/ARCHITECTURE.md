# Architecture

- `clean_mac.sh` owns category registration, orchestration and operation
  logging.
- `lib/core/executor.sh` owns Trash moves, permanent-delete routing, dry-run
  owner-command gates and identity rechecks at the mutation boundary.
- `lib/core/path_policy.sh` owns scope validation, physical-parent confinement,
  live application detection and open database/file guards.
- `lib/categories/project_artifacts.sh` owns project discovery, manifest
  evidence, scan-time identity binding and selective project cleanup.
- `lib/categories/app_uninstaller.sh` owns application discovery, bundle
  identity validation, shared-data protection and selective app cleanup.
- `lib/categories/installer_artifacts.sh` owns top-level Downloads installer
  discovery and device/inode/size/mtime-bound individual Trash moves.
- `web/server.py` owns the loopback HTTP boundary, input-shape validation,
  process isolation, bounded category workers, partial/cancelled scan assembly,
  scan deduplication, read-only health analysis, state files and application
  discovery.
- `web/script.js` owns user confirmation and selection; it sends stable category
  IDs and scan identities rather than positional category numbers.
- `web/scanutil.js` contains DOM-free scan/payload transformations tested in
  Node.

The cleanup protocol is versioned by `plan_version`. Category IDs are stable;
display order is not an API. All destructive operations must terminate in
`safe_rm`, `safe_rm_contents`, or `run_mutating_action`. CI enforces this sink
contract.

The dashboard scan invokes `--scan-category-json <stable-id>` in at most four
process groups at a time. Each worker has its own deadline. Completed category
records remain usable if another worker fails or is cancelled; unavailable
categories are disabled in the UI and never retain a stale selection.

Future module extraction should preserve this boundary: category modules may
discover candidates, but only the core executor may mutate them.

## Live file inventory

`web/file_scanner.py` implements read-only Large Files and Duplicate Files
inventories. `/api/large-files` and `/api/duplicates` enumerate the current home
directory without retaining a result cache. Large files have logical sizes of
at least 100 MiB. Duplicates are grouped by size, then verified with SHA-256;
multiple hard links to one inode count once. Files are checked for changes
before/after hashing and again before response assembly. These are snapshots;
external changes after the response require **Scan again**.

The scanner excludes hidden paths, Library directories, application/photo
bundles, dependency directories, symlinks and known cloud placeholders. It has
a 20-second cooperative deadline, 100,000-entry discovery limit, 2 GiB content
read budget and 200-result display limit. Slow individual filesystem calls can
exceed the cooperative deadline. Limits and access errors produce explicit
partial-result metadata. One inventory runs at a time; overlapping requests
receive HTTP 409. No file deletion API is exposed by these views.

## Dashboard contract corrections (2026-09-09)

- Removed hard-coded demo inventories, offline app/history fixtures and false
  offline cleanup success messages.
- Removed positional category numbers from browser cleanup requests. The
  browser category IDs now match all 18 server categories; regression tests
  enforce this contract.
- Sub-item checkboxes determine the cleanup payload, including scan identities
  for project and installer artifacts. Empty or malformed explicit selections
  are rejected instead of falling back to whole-category cleanup.
- Unavailable categories lose their selection and are disabled after partial
  or failed scans. Bulk safe selection excludes caution/danger categories.
- Developer cleanup requires deliberate selection; Trash is not selected by
  default. The dashboard total uses the backend total/in_total contract rather
  than summing only the eight visible tiles.
- History uses actual operation fields (`ts`, `bytes`, `category`, `action`).

Further module extraction should focus on separating application discovery,
scheduling and HTTP transport from `server.py`, preserving the tested mutation
boundary. The shell category registry remains canonical; the browser keeps
presentation metadata and uses stable IDs, never display positions.
