#!/bin/bash
#---------------------------------------------------------------------------
# Internal_Launcher.command
#
# Hidden background launcher. Called by CLICK_TO_START.command.
# Runs web/server.py; the server opens the browser itself
# (http://localhost:8080). Closing this window stops the server.
#---------------------------------------------------------------------------

# Move into this script's folder (no matter where the double-click came from)
cd "$(dirname "$0")" || exit 1

PORT=8080

# Check for python3 — if missing, point the user to the installer
if ! command -v python3 >/dev/null 2>&1; then
	echo "ERROR: python3 not found."
	echo "Install the macOS Command Line Tools in a new Terminal: xcode-select --install"
	echo "Press Enter in this window to close."
	read -r _
	exit 1
fi

echo "🍎 Starting Apple Cleanup...  http://localhost:${PORT}"
echo "   Close this window or press Ctrl+C to stop."
echo ""

# Capture everything to a log file next to this script so startup errors are
# recoverable even after the window closes. `python3 -u` keeps output unbuffered
# so the log is complete (and live) even if the server crashes.
LOG_FILE="$(dirname "$0")/cleanup-log.txt"
echo "   Log: ${LOG_FILE}"
echo ""
exec python3 -u web/server.py 2>&1 | tee "$LOG_FILE"
