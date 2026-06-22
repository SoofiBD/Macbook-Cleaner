#!/bin/bash
#---------------------------------------------------------------------------
# diagnose.command
#
# Double-click to collect a diagnostic log when the dashboard's Scan button
# fails ("server not running" / "scan failed"). Captures the environment plus
# a real run of `clean_mac.sh --scan-json` (timing, exit code, stderr, JSON
# validity) into diagnose-log.txt next to this file. Send that file back.
#
# First launch: RIGHT-CLICK -> "Open" to pass Gatekeeper. Nothing is changed
# or deleted — this only reads and reports.
#---------------------------------------------------------------------------

# Move into this script's folder no matter where it was launched from
cd "$(dirname "$0")" || exit 1

LOG="$(pwd)/diagnose-log.txt"

{
	echo "=== Apple Cleanup diagnostic — $(date) ==="
	echo "folder: $(pwd)"
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
		bash clean_mac.sh --scan-json > scan-out.json 2> scan-err.txt
		code=$?
		end=$(date +%s)
		echo "exit code: $code"
		echo "duration:  $((end - start)) seconds"
		echo "stdout bytes: $(wc -c < scan-out.json | tr -d ' ')"
		echo "--- stderr (first 50 lines) ---"
		head -50 scan-err.txt
		echo "--- JSON valid? ---"
		python3 -c "import json,sys; json.load(open('scan-out.json')); print('JSON OK')" 2>&1 | head -5
	fi
	echo
	echo "=== done ==="
} 2>&1 | tee "$LOG"

echo
echo "Log written to: $LOG"
echo "Send that file back. Press Enter to close this window."
read -r _
