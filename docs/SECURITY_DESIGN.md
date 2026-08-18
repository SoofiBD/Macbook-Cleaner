# Security design

## Trust boundaries

The browser, HTTP request body, environment variables, scan output retained by
the browser, filesystem names, symlinks, application metadata, and operation
log are untrusted inputs. `clean_mac.sh` is the final deletion authority; Python
validation is an additional gate, not a replacement for sink validation.

## Deletion pipeline

1. A scan emits a versioned plan with stable category IDs, risk and recovery
   metadata.
2. Selective project targets carry a scan-time identity covering the artifact,
   parent directory and authorizing manifest.
3. The shell validates absolute syntax, traversal, control characters,
   protected roots, logical scope and physical-parent scope.
4. Sensitive cache/profile paths are checked for a running owning bundle and
   open files. If `lsof` cannot verify a directory containing SQLite/WAL data,
   the target is skipped.
5. The target identity is checked immediately before the mutation.
6. User data is moved to an owned Trash directory where possible. Permanent
   categories use the same path validator before `rm`.
7. A private operation log records the source, known Trash destination,
   category and recovery status.

## Dry-run

File mutations and owner commands such as Docker, Homebrew, CoreSimulator and
QuickLook pass through shared dry-run gates. The permanent-delete test escape
hatch additionally requires test mode and a temporary HOME. The web server
removes both test-only variables from child environments.

## Known limits

- POSIX path operations cannot make the final path lookup fully race-free
  without an `openat`/file-descriptor-based native helper. Identity is checked
  twice and the physical parent is revalidated to narrow this window.
- Finder can choose a collision-renamed Trash destination. If the destination
  cannot be proven, history records the action but does not promise in-app
  restore; Finder may still offer Put Back.
- Runtime behavior on newly released macOS versions must be validated by the CI
  support matrix before claiming support.
