#!/bin/zsh
# Build, bundle, and install DevCommand.app into /Applications, then relaunch it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/scripts/bundle-app.sh" release

echo "▶ Replacing /Applications/DevCommand.app…"
osascript -e 'tell application "DevCommand" to quit' >/dev/null 2>&1 || true
pkill -x DevCommand >/dev/null 2>&1 || true
sleep 1
rm -rf "/Applications/DevCommand.app"
cp -R "$ROOT/DevCommand.app" "/Applications/DevCommand.app"

# Record where we were built from so the in-app "Check for Updates" can pull + rebuild.
defaults write com.eno.devcommand sourceRepo "$ROOT" >/dev/null 2>&1 || true

echo "▶ Launching…"
open "/Applications/DevCommand.app"
echo "✓ Installed. Look for the 📦 box icon in your menu bar (top-right)."
