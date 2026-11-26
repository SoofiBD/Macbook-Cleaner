# Clean Mac (apple-cleanup)

> A free, auditable macOS cleaner that shows you exactly what it will remove,
> moves your files to the Trash instead of deleting them, and runs entirely on
> what already ships with your Mac.

[![CI](https://github.com/SoofiBD/Macbook-Cleaner/actions/workflows/ci.yml/badge.svg)](https://github.com/SoofiBD/Macbook-Cleaner/actions/workflows/ci.yml)
[![macOS](https://img.shields.io/badge/macOS-13%2B-blue)](#requirements)
[![License](https://img.shields.io/badge/License-MIT-yellow)](LICENSE)

Clean Mac frees disk space taken by caches, logs, developer build output,
leftover app data, old installers and stale project folders. You can use it
from a local web dashboard or from the terminal. Every run scans first, shows
sizes per item, and asks before it changes anything.

---

## Why use it

Most Mac cleaners ask you to trust a closed binary with permission to delete
files. Clean Mac takes the opposite approach.

- **You can read every line that deletes.** The cleanup engine is plain Bash
  (about 4,000 lines), and all file removal goes through three functions in
  [`lib/core/executor.sh`](lib/core/executor.sh). CI fails if any other code
  path runs a recursive `rm`.
- **Trash first, not delete first.** User data is moved to the Trash and logged,
  so you can restore it from the dashboard's history. Only categories that are
  permanent by nature (emptying the Trash, system caches, temp files) delete
  directly, and they are labelled as such.
- **Preview everything.** Dry-run mode (`APPLE_CLEANUP_DRYRUN=1` or the
  dashboard switch) reports what would be removed and changes nothing.
- **Nothing to install, nothing phones home.** No compiler, no `npm install`,
  no `pip install`, no CDN, no telemetry, no account. The dashboard is a
  standard-library Python server bound to `127.0.0.1` only.
- **Built for developers too.** It understands 40+ developer caches (Xcode
  DerivedData per project, simulators, Homebrew, npm/pnpm/yarn/bun, pip/uv,
  Cargo, Gradle, CocoaPods, Flutter, JetBrains, Playwright, Hugging Face and
  more) and finds stale `node_modules`, `target`, `build`, `.build`, `vendor`,
  `.dart_tool` and `.terraform` folders next to real project manifests.
- **Fails closed.** Unknown paths, symlink escapes, changed files, running
  browsers and open databases are skipped, not guessed at.

### How it compares

| | Clean Mac | CleanMyMac | Mole | Pearcleaner / AppCleaner | OnyX |
|---|---|---|---|---|---|
| Price | Free, MIT | Paid subscription | Free | Free | Free |
| Source you can audit | Yes (Bash + Python) | No | Yes | Pearcleaner yes, AppCleaner no | No |
| Install needed | None (or Homebrew) | App | Homebrew | App | App |
| Web dashboard + terminal | Both | GUI | Terminal | GUI | GUI |
| Moves to Trash with restore history | Yes | Partly | Partly | Yes | No |
| Dry-run preview | Yes | No | Yes | No | No |
| Developer caches and project folders | Yes | Partly | Yes | No | No |
| App uninstaller with leftovers | Yes | Yes | Yes | Yes (core feature) | No |
| Disk-full forecast | Yes | No | No | No | No |

Pick a dedicated tool if you only need one job done very well (for example
Pearcleaner for uninstalling apps). Pick Clean Mac if you want one free,
transparent tool that covers caches, developer junk, apps and old installers,
and that you can review before you let it touch your disk.

---

## Quick start

### Option 1: Double-click (no Terminal needed)

1. Click the green **Code** button on this page, then **Download ZIP**.
2. Double-click the ZIP to extract it.
3. Right-click **`CLICK_TO_START.command`**, choose **Open**, then click
   **Open** again.

The dashboard opens in your browser at `http://127.0.0.1:8080`. To stop it,
close the Terminal window that opened.

Right-click → Open is only needed the first time, because macOS blocks files
downloaded from the internet. The launcher removes that block from itself and
its helper script only, never from the whole folder.

### Option 2: Homebrew

```bash
brew tap SoofiBD/apple-cleanup https://github.com/SoofiBD/Macbook-Cleaner
brew trust SoofiBD/apple-cleanup
brew install apple-cleanup
```

Then run `apple-cleanup` (dashboard) or `apple-cleanup-cli` (terminal).
Homebrew installs the latest tagged release, which can be older than `main`.
The `brew trust` step is needed because the tap lives in this repository
instead of a `homebrew-*` repository.

### Option 3: From source

```bash
git clone https://github.com/SoofiBD/Macbook-Cleaner.git
cd Macbook-Cleaner
python3 web/server.py        # dashboard
bash clean_mac.sh            # terminal interface
```

Set `APPLE_CLEANUP_OPEN_BROWSER=0` to stop the dashboard from opening a
browser tab.

### Requirements

- macOS 13 or later (CI runs on macOS 14 and 15).
- Python 3.9 or later for the dashboard. The stock `/usr/bin/python3` works.
  If it is missing, run `xcode-select --install`.
- Full Disk Access for your terminal app if you want protected locations
  scanned: **System Settings → Privacy & Security → Full Disk Access**.

---

## What it cleans

| Category | What | How it is removed |
|---|---|---|
| User caches | `~/Library/Caches/*` | Trash; skipped while the owning app runs |
| System caches | `/Library/Caches/*` | Permanent; terminal mode with `sudo` only |
| App leftovers | Folders in `~/Library/Application Support` | Trash; you pick each one |
| Logs | `~/Library/Logs`, `/Library/Logs` | Trash |
| Temporary files | Per-user temp and cache folders | Permanent; only entries idle for 2+ days; opt-in |
| Developer | Xcode, simulators, package-manager and IDE caches | Per item; you pick each one |
| Trash | `~/.Trash` | Permanent; opt-in |
| Browser cache | Safari, Chrome, Firefox, Brave, Edge, Arc, Opera caches | Trash |
| Browser full data | Whole profiles (cookies, history) | Trash; danger level, extra confirmation; skipped while the browser runs |
| iOS backups | `~/Library/MobileSync/Backup` | You pick each backup |
| App uninstaller | App bundle plus its exact bundle-ID leftovers | Trash; Homebrew casks use `brew uninstall --zap` |
| Mail downloads | Mail attachment cache | Trash; opt-in |
| Diagnostic reports | `~/Library/Logs/DiagnosticReports` | Trash |
| QuickLook cache | Thumbnail cache | Permanent |
| Saved app state | `~/Library/Saved Application State` | Trash |
| Other volumes' Trash | `/Volumes/*/.Trashes` | Permanent; opt-in |
| Project artifacts | Stale build/dependency folders next to a manifest | Trash; bound to the scanned folder identity |
| Installer files | Large `.dmg`, `.pkg`, `.iso` at the top of `~/Downloads` | Trash; never pre-selected |

The dashboard also has read-only **Large Files** and **Duplicate Files**
views (SHA-256 verified, hard links counted once), a **Health** check, a
**Storage forecast** based on your disk-usage trend, and an optional weekly
schedule that runs only the safe categories.

**Quick Clean** (and the weekly schedule) runs only: Trash, user caches,
system caches (terminal with `sudo` only), logs and browser caches.

---

## Safety model

- **Scan, then confirm.** Nothing is removed without a scan and your
  confirmation. Danger-level categories need a second confirmation.
- **One deletion boundary.** All removals go through `safe_rm`,
  `safe_rm_contents` or `run_mutating_action`. Each target is checked again
  right before removal: absolute path, no `..`, inside an allowed scope, real
  (physical) parent still inside that scope.
- **Identity binding.** Project artifacts and installer files are tied to the
  device/inode (and size/mtime for installers) seen during the scan. If the
  file changed since, it is skipped.
- **Live-data guards.** Browser profiles, caches of running apps and open
  SQLite/WAL databases are skipped.
- **Your exclusions win.** Set `APPLE_CLEANUP_EXCLUDE` to a colon-separated
  list of paths or globs. `~`, trailing slashes and different letter case are
  handled:

  ```bash
  APPLE_CLEANUP_EXCLUDE="~/Library/Caches/com.myapp:*/Important*" bash clean_mac.sh
  ```

- **Locked-down dashboard.** Loopback only, `Host`/`Origin` checks against DNS
  rebinding, a new session token on each start for every write request, one
  destructive operation at a time, and child processes stopped when the server
  stops.

The full contract is in [SECURITY.md](SECURITY.md) and
[docs/SECURITY_DESIGN.md](docs/SECURITY_DESIGN.md).

---

## Terminal and JSON interface

```bash
bash clean_mac.sh --help
bash clean_mac.sh --scan-json                         # full scan as JSON
bash clean_mac.sh --scan-category-json developer      # one category
bash clean_mac.sh --clean-ids-json user_cache,logs    # clean by stable id
APPLE_CLEANUP_DRYRUN=1 bash clean_mac.sh --clean-ids-json user_cache
bash clean_mac.sh --status-json
bash clean_mac.sh --remove-user-data                  # remove history/logs/schedule
```

Category ids are stable; display order is not part of the API.

---

## Project layout

```
clean_mac.sh               Cleanup engine and CLI (category registry, orchestration)
lib/core/executor.sh       The only code that moves or deletes files
lib/core/path_policy.sh    Scope checks, symlink confinement, live-app guards
lib/categories/            Project artifacts, app uninstaller, installer files
web/server.py              Loopback dashboard server (standard library only)
web/file_scanner.py        Read-only large/duplicate file inventory
web/index.html, script.js  Dashboard UI (vanilla JS, no build step)
Formula/apple-cleanup.rb   Homebrew formula
tests/                     Python and Node regression and security tests
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for details.

---

## Contributing

Bug reports and focused pull requests are welcome. Please read
[CONTRIBUTING.md](CONTRIBUTING.md) first: the no-dependency rule and the single
deletion boundary are not negotiable. Run the checks before opening a PR:

```bash
shellcheck --shell=bash clean_mac.sh lib/core/*.sh lib/categories/*.sh
python3 -m pytest
node --test tests/*.mjs
```

## Uninstalling

```bash
apple-cleanup-cli --remove-user-data   # or: bash clean_mac.sh --remove-user-data
brew uninstall apple-cleanup           # if installed with Homebrew
```

`--remove-user-data` moves the history, logs (`~/.cache/apple-cleanup`) and
the weekly LaunchAgent to the Trash.

## License

MIT. See [LICENSE](LICENSE). Mole was used only as an architectural reference;
no GPLv3 code or branding is included. See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
