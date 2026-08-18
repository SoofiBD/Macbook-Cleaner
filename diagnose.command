#!/bin/bash
#---------------------------------------------------------------------------
# diagnose.command
#
# Double-click to collect a diagnostic log when the dashboard's Scan button
# fails ("server not running" / "scan failed"). Captures the environment plus
# a real run of `clean_mac.sh --scan-json` (timing, exit code, stderr, JSON
# validity) into diagnose-log.txt next to this file. Review it before sharing.
#
# First launch: RIGHT-CLICK -> "Open" to pass Gatekeeper. This does not clean
# anything, but it creates a private diagnostic log next to this file.
#---------------------------------------------------------------------------

# Move into this script's folder no matter where it was launched from
cd "$(dirname "$0")" || exit 1
umask 077

LOG="$(pwd)/diagnose-log.txt"
DIAG_TMP=$(mktemp -d "${TMPDIR:-/tmp}/apple-cleanup-diagnose.XXXXXX") || exit 1
trap 'rm -rf "$DIAG_TMP"' EXIT HUP INT TERM
SCAN_OUT="$DIAG_TMP/scan-out.json"
SCAN_ERR="$DIAG_TMP/scan-err.txt"

{
	echo "=== Apple Cleanup diagnostic — $(date) ==="
	echo "folder: ~/$(basename "$(pwd)")"
	echo

	echo "--- environment ---"
	if command -v python3 >/dev/null 2>&1; then
		echo "python3: $(python3 --version 2>&1)  ($(command -v python3))"
	else
		echo "python3: NOT FOUND  (install: xcode-select --install)"
	fi
	echo "bash:    $(bash --version 2>&1 | head -1)"
	echo "macOS:   $(sw_vers -productVersion 2>&1)"
	echo

	echo "--- port 8080 in use? ---"
	lsof -nP -iTCP:8080 -sTCP:LISTEN 2>/dev/null || echo "8080 free"
	echo

	echo "--- running: bash clean_mac.sh --scan-json (max ~10 min) ---"
	if [ ! -f clean_mac.sh ]; then
		echo "ERROR: clean_mac.sh not found in this folder."
	else
		start=$(date +%s)
		python3 - "$SCAN_OUT" "$SCAN_ERR" <<'PY'
import os, signal, subprocess, sys
out_path, err_path = sys.argv[1:]
with open(out_path, "w", encoding="utf-8") as stdout, \
     open(err_path, "w", encoding="utf-8") as stderr:
    process = subprocess.Popen(
        ["bash", "clean_mac.sh", "--scan-json"],
        stdout=stdout, stderr=stderr, start_new_session=True,
    )
    try:
        code = process.wait(timeout=600)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
        code = 124
sys.exit(code)
PY
		code=$?
		end=$(date +%s)
		echo "exit code: $code"
		echo "duration:  $((end - start)) seconds"
		echo "stdout bytes: $(wc -c < "$SCAN_OUT" | tr -d ' ')"
		echo "--- stderr (first 50 lines) ---"
		sed "s|$HOME|~|g" "$SCAN_ERR" | head -50
		echo "--- JSON valid? ---"
		python3 -c "import json,sys; json.load(open(sys.argv[1])); print('JSON OK')" "$SCAN_OUT" 2>&1 | head -5
	fi
	echo
	echo "=== done ==="
} 2>&1 | tee "$LOG"

echo
echo "Log written to: $LOG"
echo "Review the log for private paths before sharing it. Press Enter to close."
read -r _
