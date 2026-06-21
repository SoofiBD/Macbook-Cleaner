#!/usr/bin/osascript
--------------------------------------------------------------------------
-- CLICK_TO_START.command
--
-- Launches the Apple Cleanup dashboard with a double-click.
-- Without typing a single line in Terminal, this file:
--   1) Grants execute (+x) permission to the launcher scripts,
--   2) Clears the macOS quarantine attribute,
--   3) Runs the background Internal_Launcher.command.
--
-- NOTE: After unzipping, on the FIRST launch RIGHT-CLICK this file -> "Open"
--       (to pass the Gatekeeper warning). After that, a plain double-click
--       is enough.
--------------------------------------------------------------------------

on run
	try
		-- Find the project folder this .command file lives in
		set myPath to POSIX path of (path to me)
		set projectDir to do shell script "dirname " & quoted form of myPath
		set launcher to projectDir & "/Internal_Launcher.command"

		-- Fix permission + quarantine without using the Terminal
		do shell script "chmod +x " & quoted form of myPath & " " & quoted form of launcher
		do shell script "xattr -dr com.apple.quarantine " & quoted form of projectDir & " 2>/dev/null; true"

		-- Start the server and browser via the background launcher
		do shell script "open " & quoted form of launcher
	on error errMsg
		display dialog "An error occurred while starting:" & return & return & errMsg buttons {"OK"} default button "OK" with icon stop
	end try
end run
