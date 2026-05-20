# 🍎 Clean Mac

> A macOS system cleanup tool — simple, safe, and effective.

[![ShellCheck](https://img.shields.io/badge/ShellCheck-passing-brightgreen)](https://www.shellcheck.net/)
[![macOS](https://img.shields.io/badge/macOS-Ventura%20%7C%20Sonoma%20%7C%20Sequoia-blue)](https://www.apple.com/macos/)
[![License](https://img.shields.io/badge/License-MIT-yellow)](LICENSE)

Clean Mac safely removes unnecessary data on macOS such as caches, logs, temporary files, leftover application data, and Trash contents. It can be used from an interactive terminal interface or a lightweight web dashboard.

---

## ✨ Features

- 🔍 Scans first and asks for confirmation — no surprises
- 📊 Flexible cleanup across 7 categories
- 🌐 Lightweight web dashboard (start with a single command)
- 🛡️ Avoids touching critical system files by default
- 🍎 Compatible with Bash 3.2+ (works on all macOS releases)

---

## 🚀 Installation

```bash
git clone https://github.com/<username>/apple-cleanup.git
cd apple-cleanup
chmod +x clean_mac.sh
```

---

## 📖 Usage

### Terminal (interactive)

```bash
# Run interactive cleanup (scans first, then prompts)
bash clean_mac.sh

# Show help
bash clean_mac.sh --help
```

### Web Dashboard

```bash
python3 web/server.py
# Open your browser at http://localhost:8080
```

---

## 📦 Categories

| # | Category | Target | Notes |
|---|----------|--------|-------|
| 1 | 📦 User Caches | `~/Library/Caches/*` | |
| 2 | 🖥️ System Caches | `/Library/Caches/*` | requires `sudo` |
| 3 | 📂 App Leftovers | `~/Library/Application Support/`, `~/Library/Preferences/` | interactive selection |
| 4 | 📋 Logs | `~/Library/Logs/*`, `/Library/Logs/*` | |
| 5 | 🗃️ Temporary Files | `$TMPDIR`, user var/folders | |
| 6 | 🛠️ Developer | Xcode DerivedData, broken symlinks | interactive selection |
| 7 | 🗑️ Trash | `~/.Trash/*` | |

---

## 🏗️ Project Structure

```
apple-cleanup/
├── clean_mac.sh        # Main cleanup script
├── web/
│   ├── server.py       # Python web server for the dashboard
│   ├── index.html      # Dashboard UI
│   ├── style.css       # Styles
│   └── script.js       # Frontend logic
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

---

## ⚠️ Safety Notes

- The script only removes caches, logs, and temporary files by default.
- macOS will recreate many of these files as needed.
- The `Downloads` folder is not touched.
- System Cache cleanup requires `sudo` (terminal mode).
- The web dashboard skips categories that require `sudo` unless explicitly enabled.

---

## 📄 License

MIT License — see [LICENSE](LICENSE) for details.
