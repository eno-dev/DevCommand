#!/bin/zsh
# Regenerate the app-icon assets from assets/icon-1024.png and commit the results.
# Run this only when the logo changes — bundle-app.sh just copies what this produces.
# Needs sips + iconutil (ship with macOS) and pngquant (brew install pngquant).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
SRC="assets/icon-1024.png"
[[ -f "$SRC" ]] || { print "✗ missing $SRC" >&2; exit 1 }
command -v pngquant >/dev/null || { print "✗ pngquant not found — brew install pngquant" >&2; exit 1 }

# Lossy palette quantisation: huge size win on these flat/gradient logos, visually lossless.
Q=(--quality=70-96 --speed 1 --strip --force --ext .png)

print "▶ AppIcon.icns (capped at 512px — menu-bar app has no Dock icon)…"
TMP="$(mktemp -d)"; SET="$TMP/AppIcon.iconset"; mkdir -p "$SET"
for s in 16 32 128 256; do
  sips -z "$s" "$s" "$SRC" --out "$SET/icon_${s}x${s}.png" >/dev/null
  sips -z "$((s*2))" "$((s*2))" "$SRC" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
sips -z 512 512 "$SRC" --out "$SET/icon_512x512.png" >/dev/null
pngquant "${Q[@]}" "$SET"/*.png
iconutil -c icns "$SET" -o assets/AppIcon.icns
rm -rf "$TMP"

print "▶ Logo.png (in-app header, 128px)…"
sips -z 128 128 "$SRC" --out assets/Logo.png >/dev/null
pngquant "${Q[@]}" assets/Logo.png

print "▶ Optimising the source $SRC (used by the README too)…"
pngquant "${Q[@]}" "$SRC"

print "✓ done:"
ls -la assets/AppIcon.icns assets/Logo.png "$SRC" | awk '{print "  "$5" bytes  "$9}'
