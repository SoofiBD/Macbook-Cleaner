# Security Policy

Apple Cleanup moves or deletes local files, so deletion safety is part of its
public API rather than an implementation detail.

## Supported security contract

- Web endpoints bind to loopback and require the per-process request token.
- Cleanup targets must be absolute, traversal-free paths in an explicitly
  supported filesystem scope.
- The physical parent of a target must stay in the same scope as its logical
  path. Symlinked directory roots are not traversed for content deletion.
- Critical system roots are never cleanup targets. Downloads is protected
  except for direct `.dmg`, `.pkg`, and `.iso` files that the user selects
  individually from a fresh scan and whose filesystem identity still matches.
- Dry-run executes no file or owner-command mutation.
- User data is Trash-first unless the category is explicitly documented as
  permanent, such as emptying Trash or system cache cleanup.
- Project artifacts are tied to their scan-time device/inode identity and exact
  project manifest, then checked again immediately before Trash.
- Open cache/profile files and unverifiable SQLite/WAL targets are skipped.
- Apple-owned bundle identifiers are protected; shared data is retained while
  another application with the same bundle identifier remains installed.

The detailed trust boundaries and remaining limitations are documented in
`docs/SECURITY_DESIGN.md`.

## Reporting a vulnerability

Do not include private user paths, operation logs, or diagnostic output in a
public issue. Contact the repository owner privately first and provide the
smallest reproduction possible using an isolated temporary HOME.

## Verification

Run:

```bash
for file in clean_mac.sh lib/core/*.sh lib/categories/*.sh; do bash -n "$file"; done
shellcheck clean_mac.sh lib/core/*.sh lib/categories/*.sh
python3 -m pytest
node --test tests/*.mjs
node --check web/script.js
```

Security contract tests additionally reject recursive quarantine clearing,
unmediated recursive `rm`, and shell-enabled Python subprocesses.
