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
