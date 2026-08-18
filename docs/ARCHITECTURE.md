# Architecture

- `clean_mac.sh` owns category registration, scanning, deletion validation,
  execution and operation logging.
- `web/server.py` owns the loopback HTTP boundary, input-shape validation,
  process isolation, scan deduplication, state files and application discovery.
- `web/script.js` owns user confirmation and selection; it sends stable category
  IDs and scan identities rather than positional category numbers.
- `web/scanutil.js` contains DOM-free scan/payload transformations tested in
  Node.

The cleanup protocol is versioned by `plan_version`. Category IDs are stable;
display order is not an API. All destructive operations must terminate in
`safe_rm`, `safe_rm_contents`, or `run_mutating_action`. CI enforces this sink
contract.

Future module extraction should preserve this boundary: category modules may
discover candidates, but only the core executor may mutate them.
