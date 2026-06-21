# 🍎 Clean Mac

> A comprehensive macOS system cleanup tool — simple, safe, and effective.

[![ShellCheck](https://img.shields.io/badge/ShellCheck-passing-brightgreen)](https://www.shellcheck.net/)
[![macOS](https://img.shields.io/badge/macOS-Ventura%20%7C%20Sonoma%20%7C%20Sequoia-blue)](https://www.apple.com/macos/)
[![License](https://img.shields.io/badge/License-MIT-yellow)](LICENSE)

Clean Mac safely removes unnecessary data on macOS such as caches, logs, temporary files, leftover application data, and Trash contents. It can be used from an interactive terminal interface or a lightweight web dashboard.

> **Lightweight & no-compiler philosophy:** This tool is deliberately
> minimalist. There is **no** build step, no `npm install`, no compiler, and no
> external dependency. A single-file server runs on the built-in Python, with
> vanilla JavaScript and locally vendored animation libraries — **no CDN or
> network required**.

---

## 🖱️ Easy Setup & Usage (No technical knowledge needed)

You don't need to know the Terminal. Three steps:

1. **Download:** Click the green **`Code`** button at the top of this page →
   **`Download ZIP`**.
2. **Extract:** Double-click the downloaded ZIP; a folder is created.
3. **Start:** Inside the folder, **right-click `CLICK_TO_START.command` → "Open"**,
   then click **"Open"** again in the warning dialog.

The dashboard opens automatically in your browser at `http://localhost:8080`. 🎉

> **Why "right-click → Open" the first time?** macOS locks files downloaded from
> the internet for security. Right-click → "Open" clears that lock once, safely.
> After the first launch, a **plain double-click** is enough — the file clears
> its own permissions and the macOS quarantine for you, with nothing to type in
> the Terminal.
>
> To quit, just close the black Terminal window that opened.

> **Note:** The tool only requires Python 3, which ships with modern macOS. If
> it's missing, the Terminal window points you to `xcode-select --install`.

---

## ✨ Features

- 🔍 Scans first and asks for confirmation — no surprises
- 📊 Flexible cleanup across **17 categories**
- 🧑‍💻 Deep **developer cleanup** — 40+ caches: Xcode/simulators, Homebrew, npm/pnpm/yarn/bun/deno, pip/uv/poetry/conda, Go, Rust Cargo, Gradle/Maven/SBT/Bazel, CocoaPods/Carthage, Composer, Flutter, JetBrains, Playwright/Puppeteer/Prisma, HuggingFace, and more — each with a plain-language description of what it is and how it rebuilds, plus a per-project breakdown of Xcode DerivedData (e.g. *MyApp: 2.3 GB, ClientSDK: 1.1 GB*)
- 🗑️ **App Uninstaller** — remove apps and their leftovers, with Homebrew-cask awareness, from the dashboard
- 🧱 **Project Artifact Scanner** — finds stale `node_modules`/`target`/`.build`/`build`/`vendor`/`.dart_tool`/`.terraform` next to a project manifest in your code folders; stale (>30 days) ones are pre-selected
- 📈 **Storage forecast** — records disk-usage history and predicts when your disk will fill (least-squares trend over the last 90 days)
- 🌐 Lightweight web dashboard (start with a single command), animated with **GSAP** (vendored locally — no CDN/network), with reduced-motion support and full graceful fallback if scripts fail to load
- 🛡️ Avoids touching critical system files by default
- 🍎 Compatible with Bash 3.2+ (works on all macOS releases)

---

## 🧑‍💻 Advanced / Terminal Usage

For those who prefer the Terminal. (The double-click method above does all of
this in the background.)

### Installation

```bash
git clone https://github.com/<username>/apple-cleanup.git
cd apple-cleanup
chmod +x clean_mac.sh
```

### Interactive (terminal interface)

```bash
# Scans first, then prompts for confirmation
bash clean_mac.sh

# Help
bash clean_mac.sh --help
```

### Web Dashboard

```bash
python3 web/server.py
# The browser opens automatically: http://localhost:8080
```

To prevent the browser from opening automatically:

```bash
APPLE_CLEANUP_OPEN_BROWSER=0 python3 web/server.py
```

---

## 📦 Cleanup Categories

The script targets a wide array of system and user items, categorized by safety levels:

| # | Category | Target / Description | Notes |
|---|----------|----------------------|-------|
| 1 | 📦 User Caches | `~/Library/Caches/*` | Safe |
| 2 | 🖥️ System Caches | `/Library/Caches/*` | requires `sudo` |
| 3 | 📂 App Leftovers | `~/Library/Application Support/` | interactive selection |
| 4 | 📋 Logs | `~/Library/Logs/*`, `/Library/Logs/*` | Safe |
| 5 | 🗃️ Temporary Files | `$TMPDIR`, user var/folders | Safe |
| 6 | 🛠️ Developer | Xcode DerivedData | interactive selection |
| 7 | 🗑️ Trash | `~/.Trash/*` | Safe |
| 8 | 🌐 Browser Cache | `~/Library/Caches` for Safari, Chrome, etc. | Safe |
| 9 | ⚠️ Browser Full Data | Complete browser profiles (cookies, history) | **Danger** (requires opt-in) |
| 10| 📱 iOS Backups | `~/Library/MobileSync/Backup` | interactive selection |
| 11| 🗑️ App Uninstaller | Remove apps & associated leftover files | interactive selection |
| 12| 📨 Mail Downloads | Mail attachment downloads cache | Safe |
| 13| 🩺 Diagnostic Reports| `~/Library/Logs/DiagnosticReports` | Safe |
| 14| 🖼️ QuickLook Cache | `qlmanage` thumbnail cache | Safe |
| 15| 💾 Saved App State | `~/Library/Saved Application State` | Caution |
| 16| 💽 Other Trashes | `/Volumes/*/.Trashes` | Safe |
| 17| 🧱 Project Artifacts | Stale `node_modules`, `target`, `.build`, `build`, `vendor`, `.dart_tool`, `.terraform` in code folders | interactive selection |

---

## 🏗️ Project Structure

```
apple-cleanup/
├── CLICK_TO_START.command    # Double-click launcher (fixes perms/quarantine)
├── Internal_Launcher.command # Background: runs the server
├── clean_mac.sh              # Main cleanup script
├── web/
│   ├── server.py             # Python web server for the dashboard
│   ├── index.html            # Dashboard UI
│   ├── style.css             # Styles
│   ├── script.js             # Frontend logic
│   └── vendor/               # Vendored GSAP (no CDN/network)
├── README.md
├── LICENSE
└── .gitignore
```

---

## 🔧 Web API

The web dashboard invokes `clean_mac.sh` in JSON mode for programmatic control:

```bash
# Get scan results
bash clean_mac.sh --scan-json

# Clean specific categories (comma-separated indices)
bash clean_mac.sh --clean-json 1,4,7

# Get system status
bash clean_mac.sh --status-json
```

The dashboard also exposes two HTTP endpoints used by the **App Uninstaller**
tab (loopback + session-token protected, like every other write endpoint):

- `GET /api/apps` — enumerate installed apps (`/Applications`, `~/Applications`)
  and Homebrew casks, with sizes and bundle IDs.
- `POST /api/uninstall` — remove an app and its leftovers and/or run
  `brew uninstall`. App and Homebrew names are validated before use.
- `GET /api/forecast` — records a disk-usage snapshot (max once/hour, 90-day
  retention in `~/.cache/apple-cleanup/`) and returns a least-squares estimate
  of days until the disk is full, plus the daily growth rate.

---

## ⚠️ Safety Notes

- The script only removes caches, logs, and temporary files by default.
- macOS will recreate many of these files as needed.
- The `Downloads` folder is not touched.
- System Cache cleanup requires `sudo` (terminal mode).
- The web dashboard skips categories that require `sudo` unless explicitly enabled.
- **Dry-run preview:** set `APPLE_CLEANUP_DRYRUN=1` (or tick *Önizleme* in the
  dashboard) to see exactly what would be removed — nothing is deleted.
- **Exclusion list:** set `APPLE_CLEANUP_EXCLUDE` to a colon-separated list of
  paths/globs to protect from deletion, e.g.
  `APPLE_CLEANUP_EXCLUDE="$HOME/Library/Caches/com.myapp:*/Important*"`.

## 🔒 Web Dashboard Security

The dashboard exposes an API that can delete files, so it is locked down:

- Binds to **loopback only** (`127.0.0.1`) — never reachable from the LAN.
- Rejects requests whose `Host`/`Origin` is not loopback (anti DNS-rebinding/CSRF).
- Requires a **per-session token** (regenerated on each start) on every
  destructive request; no wildcard CORS is sent.

---

## 📄 License

MIT License — see [LICENSE](LICENSE) for details.
