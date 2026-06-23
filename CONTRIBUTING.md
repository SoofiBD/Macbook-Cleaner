# Contributing to Clean Mac

Thanks for taking the time to contribute! Clean Mac is a lightweight, minimalist,
and security-focused macOS cleanup tool, and we welcome bug reports, fixes,
documentation, and well-scoped features.

Before you write code, please read the architectural constraints below — they are
the whole point of the project, and PRs that break them cannot be merged.

## Architectural Constraints (non-negotiable)

Clean Mac follows a strict **no-dependency / no-compiler** philosophy. Keep this in
mind for every change:

- **No external npm dependencies.** No `package.json` dependency tree, no
  `npm install`, no `node_modules`. The frontend is **pure vanilla JavaScript**.
- **No build step.** No webpack, Vite, Babel, TypeScript compilation, or bundlers.
  What you write is what ships. The browser loads the source files directly.
- **No CDNs or external network requests.** The dashboard must work fully offline.
  Do not add `<script src="https://...">`, web fonts, analytics, or telemetry.
- **GSAP stays local.** Animation libraries live in `web/vendor/` and are loaded
  from disk. Do not swap them for a CDN link or add new third-party JS libraries.
- **Backend = built-in Python 3 only.** `web/server.py` uses the standard library
  (`http.server`, `json`, etc.). No `pip install`, no Flask/FastAPI/Django.
- **Cleanup logic = portable Bash.** `clean_mac.sh` targets macOS and must pass
  ShellCheck. Guard destructive operations and never touch protected system paths.

If you think a change genuinely needs a dependency, open an issue to discuss it
**before** writing code. The default answer is "vendor it locally or do without."

## Project Layout

| Path | Purpose |
|------|---------|
| `clean_mac.sh` | Main cleanup script (Bash) |
| `web/server.py` | Local Python dashboard server |
| `web/index.html`, `style.css`, `script.js` | Dashboard UI (vanilla) |
| `web/vendor/` | Locally vendored GSAP — no CDN |
| `tests/` | Python `unittest` + Node `node:test` suites |

## Getting Started

1. Fork the repository and clone your fork.
2. Create a branch off `main`: `git checkout -b fix/short-description`.
3. Make your change, keeping it focused and small.

You need only what macOS already ships: `bash`, `python3`, and (for the JS test)
`node`. Nothing to install.

## Running the Test Suite Locally

Run **all** of these before opening a PR — CI runs the same checks.

**1. ShellCheck the cleanup script** (matches the `shellcheck` CI job):

```bash
# Install once via Homebrew if you don't have it:
#   brew install shellcheck
shellcheck --shell=bash clean_mac.sh
```

**2. Python unit tests** (built-in `unittest`, no dependencies):

```bash
python3 -m unittest discover -s tests -p "test_*.py" -v
```

**3. JavaScript unit tests** (Node's built-in test runner):

```bash
node --test tests/
```

**4. Smoke-test the app** by double-clicking `CLICK_TO_START.command`, or run the
server directly and open the dashboard in your browser to confirm nothing broke.

## Submitting a Pull Request

- Make sure all three test commands above pass.
- Fill out the pull request template completely, including the dependency checklist.
- Keep the diff scoped to one logical change. Separate unrelated fixes into
  separate PRs.
- Write a clear description of **what** changed and **why**.

## Reporting Bugs and Requesting Features

Use the issue templates (Bug Report / Feature Request). Include your macOS version,
how you launched the tool, and exact steps to reproduce.

By contributing, you agree that your contributions are licensed under the same
license as this project (see `LICENSE`).
