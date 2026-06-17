#!/bin/zsh
# Remove DevCommand.app and its preferences. (The app's own Settings → Uninstall does the
# same thing plus removes the launch-at-login item — prefer that when the app is running.)
set -euo pipefail

echo "▶ Quitting DevCommand…"
osascript -e 'tell application "DevCommand" to quit' >/dev/null 2>&1 || true
pkill -x DevCommand >/dev/null 2>&1 || true
sleep 1

echo "▶ Removing /Applications/DevCommand.app…"
rm -rf "/Applications/DevCommand.app"

echo "▶ Clearing preferences…"
defaults delete com.eno.devcommand >/dev/null 2>&1 || true

echo "✓ DevCommand uninstalled."
