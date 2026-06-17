#!/bin/zsh
# Assemble DevCommand.app — a LSUIElement (menu-bar-only) bundle around the SwiftPM binary.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
CONFIG="${1:-release}"
APP="DevCommand.app"
VERSION="${DEVCOMMAND_VERSION:-0.1.0}"   # marketing version (CFBundleShortVersionString)
BUILD="${DEVCOMMAND_BUILD:-1}"           # build number (CFBundleVersion); release.sh sets it from git
# Validate before substituting into the plist below, so a stray value can't break or inject the XML.
[[ "$VERSION" =~ '^[0-9]+(\.[0-9]+){1,2}$' ]] || { echo "✗ invalid DEVCOMMAND_VERSION: $VERSION" >&2; exit 1; }
[[ "$BUILD" =~ '^[0-9]+$' ]] || { echo "✗ invalid DEVCOMMAND_BUILD: $BUILD" >&2; exit 1; }

echo "▶ Building ($CONFIG)…"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/DevCommand"

echo "▶ Assembling $APP ($VERSION build $BUILD)…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DevCommand"
printf 'APPL????' > "$APP/Contents/PkgInfo"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>             <string>DevCommand</string>
    <key>CFBundleDisplayName</key>      <string>DevCommand</string>
    <key>CFBundleIdentifier</key>       <string>com.eno.devcommand</string>
    <key>CFBundleVersion</key>          <string>__BUILD__</string>
    <key>CFBundleShortVersionString</key><string>__VERSION__</string>
    <key>CFBundleExecutable</key>       <string>DevCommand</string>
    <key>CFBundleIconFile</key>         <string>AppIcon</string>
    <key>CFBundlePackageType</key>      <string>APPL</string>
    <key>LSMinimumSystemVersion</key>   <string>14.0</string>
    <key>LSUIElement</key>              <true/>
    <key>NSPrincipalClass</key>         <string>NSApplication</string>
    <key>NSHumanReadableCopyright</key> <string>DevCommand, a local developer cockpit</string>
    <key>NSAppleEventsUsageDescription</key> <string>DevCommand uses AppleScript to run your commands in Terminal or iTerm and to show or hide those windows.</string>
</dict>
</plist>
PLIST

# Substitute the validated version/build into the static plist (the quoted heredoc never expands,
# so nothing in the plist body — now or later — can accidentally expand a $ or backtick).
/usr/bin/sed -i '' -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" "$APP/Contents/Info.plist"

# App icon + in-app header logo: copy the pre-optimised assets.
# Regenerate them from assets/icon-1024.png with scripts/make-icon.sh when the logo changes.
[[ -f assets/AppIcon.icns ]] && cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
[[ -f assets/Logo.png ]]     && cp assets/Logo.png     "$APP/Contents/Resources/Logo.png"

echo "▶ Code signing (ad-hoc)…"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || echo "  (ad-hoc sign skipped)"

echo "✓ Built $ROOT/$APP"
