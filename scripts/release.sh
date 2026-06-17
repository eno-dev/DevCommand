#!/bin/zsh
# DevCommand release pipeline — one command does the lot:
#   build → sign (Developer ID + hardened runtime) → .dmg → notarize → staple
#         → GitHub Release → Homebrew tap bump.
#
#   zsh scripts/release.sh 0.2.0               # full release
#   zsh scripts/release.sh 0.2.0 --no-publish  # build + sign + notarize only (no GitHub / brew)
#
# Config is read from .env (gitignored) — copy .env.example and fill it in. See docs/RELEASING.md.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

info()    { print -P "%F{cyan}▶%f $*"; }
success() { print -P "%F{green}✓%f $*"; }
warn()    { print -P "%F{yellow}⚠%f $*"; }
die()     { print -P "%F{red}✗ $*%f" >&2; exit 1; }

print_cask() {   # $1 version  $2 sha256
  cat <<EOF
cask "devcommand" do
  version "$1"
  sha256 "$2"

  url "https://github.com/eno-dev/DevCommand/releases/download/v#{version}/DevCommand.dmg"
  name "DevCommand"
  desc "Menu-bar cockpit for React, React Native, web, and backend developers"
  homepage "https://github.com/eno-dev/DevCommand"

  depends_on macos: ">= :sonoma"
  app "DevCommand.app"

  zap trash: ["~/Library/Preferences/com.eno.devcommand.plist"]
end
EOF
}

# ---- args & config ---------------------------------------------------------
VERSION="${1:-}"
[[ -n "$VERSION" ]] || die "Usage: zsh scripts/release.sh <version> [--no-publish]   (e.g. 0.2.0)"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Version must be X.Y.Z (got '$VERSION')"
PUBLISH=1
[[ "${2:-}" == "--no-publish" ]] && PUBLISH=0

[[ -f .env ]] && { set -a; source ./.env; set +a; }

: "${SIGN_IDENTITY:?Set SIGN_IDENTITY in .env — see .env.example}"
ENTITLEMENTS="${ENTITLEMENTS:-DevCommand.entitlements}"
APP="DevCommand.app"
DMG="DevCommand.dmg"
TAG="v$VERSION"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

notary=()
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  notary=(--keychain-profile "$NOTARY_PROFILE")
elif [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" && -n "${ASC_KEY_PATH:-}" ]]; then
  notary=(--key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID")
else
  die "No notary credentials — set NOTARY_PROFILE, or ASC_KEY_ID/ASC_ISSUER_ID/ASC_KEY_PATH (see .env.example)"
fi

# ---- preflight -------------------------------------------------------------
info "Preflight…"
for t in swift codesign hdiutil xcrun shasum; do command -v "$t" >/dev/null || die "missing tool: $t"; done
security find-identity -v -p codesigning | grep -qF "$SIGN_IDENTITY" \
  || die "signing identity not in keychain: $SIGN_IDENTITY"
[[ -f "$ENTITLEMENTS" ]] || die "entitlements file missing: $ENTITLEMENTS"
success "tools + identity OK"

# ---- build & assemble ------------------------------------------------------
info "Building DevCommand $VERSION (build $BUILD_NUMBER)…"
DEVCOMMAND_VERSION="$VERSION" DEVCOMMAND_BUILD="$BUILD_NUMBER" zsh scripts/bundle-app.sh release >/dev/null
success "assembled $APP"

# ---- sign the app ----------------------------------------------------------
info "Signing the app (Developer ID + hardened runtime)…"
codesign --force --options runtime --timestamp --entitlements "$ENTITLEMENTS" \
  --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP" || die "codesign verify failed"
success "app signed & verified"

# ---- notarize + staple the APP (pass 1) ------------------------------------
# Notarize the app via a zip so we can staple the app itself. A dmg whose
# contained app has no stapled ticket can read as "damaged" on download.
info "Notarizing the app (a few minutes)…"
rm -f DevCommand-app.zip
ditto -c -k --keepParent "$APP" DevCommand-app.zip
xcrun notarytool submit DevCommand-app.zip "${notary[@]}" --wait \
  || die "app notarization failed — xcrun notarytool log <submission-id> ${notary[*]}"
xcrun stapler staple "$APP" || die "stapling the app failed"
rm -f DevCommand-app.zip
success "app notarized & stapled"

# ---- package the dmg (drag-to-Applications layout) from the stapled app -----
info "Packaging + signing $DMG…"
rm -f "$DMG"
hdiutil detach /Volumes/DevCommand >/dev/null 2>&1 || true   # clear a stale mount
STAGE="$(mktemp -d)"; RWDIR="$(mktemp -d)"; RW="$RWDIR/rw.dmg"
ditto "$APP" "$STAGE/$APP"                  # the stapled app
ln -s /Applications "$STAGE/Applications"   # the drag-to-install target
hdiutil create -volname DevCommand -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$RW" >/dev/null
MOUNT="$(hdiutil attach "$RW" -nobrowse -noverify -noautoopen | grep -o '/Volumes/.*' | head -1)"
# Best-effort Finder layout: icon view, app on the left, the Applications folder on the right.
osascript >/dev/null 2>&1 <<'OSA' || warn "skipped the Finder layout (the dmg is still valid)"
tell application "Finder"
  tell disk "DevCommand"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 760, 480}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 104
    set position of item "DevCommand.app" of container window to {150, 190}
    set position of item "Applications" of container window to {410, 190}
    update without registering applications
    delay 1
    close
  end tell
end tell
OSA
sync
hdiutil detach "$MOUNT" >/dev/null 2>&1 || hdiutil detach "$MOUNT" -force >/dev/null 2>&1 || true
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG" >/dev/null
rm -rf "$STAGE" "$RWDIR"
codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
codesign --verify --verbose=2 "$DMG" || die "dmg codesign verify failed"
success "dmg built & signed (drag-to-Applications)"

# ---- notarize + staple the DMG (pass 2) ------------------------------------
info "Notarizing the dmg…"
xcrun notarytool submit "$DMG" "${notary[@]}" --wait \
  || die "dmg notarization failed — xcrun notarytool log <submission-id> ${notary[*]}"
xcrun stapler staple "$DMG" || die "stapling the dmg failed"
SHA="$(shasum -a 256 "$DMG" | awk '{print $1}')"
success "dmg notarized & stapled — sha256 $SHA"

if (( ! PUBLISH )); then
  print ""
  success "Done (--no-publish). Artifact: $ROOT/$DMG"
  exit 0
fi

# ---- GitHub release --------------------------------------------------------
command -v gh >/dev/null || die "gh not installed — brew install gh (or re-run with --no-publish)"
gh auth status >/dev/null 2>&1 || die "gh not authenticated — run: gh auth login"
git remote get-url origin >/dev/null 2>&1 || die "no 'origin' remote — push the repo to GitHub first"

info "Publishing GitHub release $TAG…"
notes="$(mktemp)"
awk -v v="$VERSION" '$0 ~ "^## \\[" v "\\]" {f=1;next} /^## \[/{f=0} f' CHANGELOG.md > "$notes"
[[ -s "$notes" ]] || awk '/^## \[Unreleased\]/{f=1;next} /^## \[/{f=0} f' CHANGELOG.md > "$notes"
[[ -s "$notes" ]] || printf 'DevCommand %s\n' "$VERSION" > "$notes"   # never publish an empty release body

git tag -f "$TAG" >/dev/null            # point the tag at the commit we just built
git push -f origin "$TAG"               # publish/update the tag (a re-release moves it forward)
if gh release view "$TAG" >/dev/null 2>&1; then
  gh release upload "$TAG" "$DMG" --clobber
else
  gh release create "$TAG" "$DMG" --title "DevCommand $VERSION" --notes-file "$notes"
fi
rm -f "$notes"
URL="$(gh release view "$TAG" --json url -q .url 2>/dev/null || echo "")"
success "published ${URL:-$TAG}"

# ---- Homebrew tap ----------------------------------------------------------
if [[ -n "${HOMEBREW_TAP_DIR:-}" && -d "$HOMEBREW_TAP_DIR" ]]; then
  cask="$HOMEBREW_TAP_DIR/Casks/devcommand.rb"
  info "Updating tap cask $cask…"
  mkdir -p "$(dirname "$cask")"
  print_cask "$VERSION" "$SHA" > "$cask"
  ( cd "$HOMEBREW_TAP_DIR" && git add Casks/devcommand.rb && git commit -m "devcommand $VERSION" && git push )
  success "tap updated → users run: brew upgrade --cask devcommand"
else
  print ""
  warn "HOMEBREW_TAP_DIR not set — paste this into your tap's Casks/devcommand.rb:"
  print ""
  print_cask "$VERSION" "$SHA"
fi

print ""
print -P "%F{green}━━ released DevCommand $VERSION (build $BUILD_NUMBER) ━━%f"
print "  dmg      $ROOT/$DMG"
print "  sha256   $SHA"
print "  release  ${URL:-n/a}"
