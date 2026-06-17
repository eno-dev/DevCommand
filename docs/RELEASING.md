# Releasing DevCommand

DevCommand ships as a **signed, notarized `.dmg`** attached to a GitHub Release, and as a
**Homebrew cask** so people can `brew install --cask`. Both consume the same notarized build.

You need an **Apple Developer Program** membership ($99/yr) for signing + notarization.

```
build → sign (Developer ID + hardened runtime) → package (.dmg)
      → notarize → staple → GitHub Release → Homebrew tap
```

## The pipeline — one command

Once the one-time setup below is done, a whole release is a single command:

```sh
zsh scripts/release.sh 0.2.0                # build → sign → notarize → staple → release → tap bump
zsh scripts/release.sh 0.2.0 --no-publish   # everything except GitHub/Homebrew (a safe dry run)
```

`release.sh` reads its config from a gitignored **`.env`** — copy the template and fill it in once:

```sh
cp .env.example .env        # set SIGN_IDENTITY + notary creds (+ optional HOMEBREW_TAP_DIR)
```

It auto-bumps the build number from the git commit count, pulls release notes from `CHANGELOG.md`,
computes the dmg's `sha256`, and — when `HOMEBREW_TAP_DIR` is set — rewrites and pushes your cask.
The only thing you type per release is the version.

**Fully hands-off (CI):** push a `vX.Y.Z` tag and
[.github/workflows/release.yml](../.github/workflows/release.yml) runs the same script on a macOS
runner. It needs these repository secrets (Settings → Secrets and variables → Actions):
`MACOS_CERT_P12_BASE64`, `MACOS_CERT_PASSWORD`, `MACOS_SIGN_IDENTITY`, `KEYCHAIN_PASSWORD`,
`ASC_KEY_P8_BASE64`, `ASC_KEY_ID`, `ASC_ISSUER_ID`.

The rest of this doc is the **one-time setup**, then each step broken out — handy for debugging or
running a step by hand.

## Prerequisites (one-time)

**Developer ID Application certificate** — the cert for distributing *outside* the App Store
(not "Apple Development" or "Mac App Store"). If you already ship an app to the App Store / TestFlight,
that uses an **Apple Distribution** cert — this is a *different* certificate, so create it even if
signing already works for your other app:

- Xcode → Settings → Accounts → *your team* → Manage Certificates → **+** → **Developer ID Application**.
- Verify it's installed and note the identity name + Team ID:
  ```sh
  security find-identity -v -p codesigning
  # → "Developer ID Application: Your Name (ABCDE12345)"
  ```

**Notary credentials** — store them once into a keychain profile so later commands just pass
`--keychain-profile devcommand-notary`. Two options:

- **App Store Connect API key** (preferred). If you already ship another app to TestFlight you almost
  certainly have one at `~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8` — the *same* key notarizes:
  ```sh
  xcrun notarytool store-credentials devcommand-notary \
    --key ~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8 \
    --key-id <KEYID> --issuer <ISSUER_UUID>
  ```
- **App-specific password** (if you have no API key) — create one at appleid.apple.com → Sign-In & Security:
  ```sh
  xcrun notarytool store-credentials devcommand-notary \
    --apple-id "you@example.com" --team-id ABCDE12345 --password "abcd-efgh-ijkl-mnop"
  ```

## 1. Build & sign

DevCommand is **not** sandboxed (it shells out to `lsof` / `xcrun` / `npm` …) — fine for Developer ID
distribution. It needs **hardened runtime** (required for notarization) plus one entitlement for the
Terminal/iTerm AppleScript control. `DevCommand.entitlements`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.automation.apple-events</key>
    <true/>
</dict>
</plist>
```
Build the bundle, then sign with Developer ID instead of the ad-hoc signature:
```sh
zsh scripts/bundle-app.sh release      # assembles DevCommand.app

codesign --force --options runtime --timestamp \
  --entitlements DevCommand.entitlements \
  --sign "Developer ID Application: Your Name (ABCDE12345)" \
  DevCommand.app

codesign --verify --strict --verbose=2 DevCommand.app    # should pass
```

## 2. Package as a `.dmg`
```sh
hdiutil create -volname "DevCommand" -srcfolder DevCommand.app -ov -format UDZO DevCommand.dmg
```
For a styled window with a drag-to-Applications shortcut, `brew install create-dmg` and use that
instead (purely cosmetic).

## 3. Notarize & staple
```sh
xcrun notarytool submit DevCommand.dmg --keychain-profile devcommand-notary --wait
#   status: Accepted  → continue
#   status: Invalid   → xcrun notarytool log <submission-id> --keychain-profile devcommand-notary

xcrun stapler staple DevCommand.dmg
spctl -a -t open --context context:primary-signature -vv DevCommand.dmg   # → accepted
```

## 4. Publish the GitHub Release
Bump `CFBundleShortVersionString` in `scripts/bundle-app.sh`, move the CHANGELOG `[Unreleased]`
items under a new version heading, then:
```sh
git tag v0.2.0 && git push origin v0.2.0
gh release create v0.2.0 DevCommand.dmg --title "DevCommand 0.2.0" \
  --notes-file <(sed -n '/## \[0.2.0\]/,/## \[0.1.0\]/p' CHANGELOG.md)
```
Keep the asset filename constant (`DevCommand.dmg`) — the tag carries the version in the URL, which
keeps the Homebrew cask trivial to bump.

## 5. Homebrew cask (your own tap)

Start with your **own tap** — the official `homebrew-cask` repo has notability requirements
(stars/forks, established history) that a brand-new project won't meet yet.

**a. Create the tap repo.** A GitHub repo named exactly `homebrew-tap` under your account
(`github.com/eno-dev/homebrew-tap`), containing a `Casks/` folder. Homebrew maps `eno-dev/tap`
→ that repo automatically.

**b. Add `Casks/devcommand.rb`:**
```ruby
cask "devcommand" do
  version "0.2.0"
  sha256 "PASTE_SHASUM_HERE"

  url "https://github.com/eno-dev/DevCommand/releases/download/v#{version}/DevCommand.dmg"
  name "DevCommand"
  desc "Menu-bar cockpit for React, React Native, web, and backend developers"
  homepage "https://github.com/eno-dev/DevCommand"

  depends_on macos: ">= :sonoma"   # macOS 14+

  app "DevCommand.app"

  zap trash: [
    "~/Library/Preferences/com.eno.devcommand.plist",
    "~/Library/Saved Application State/com.eno.devcommand.savedState",
  ]
end
```
Compute the checksum for the `sha256` line from the notarized dmg:
```sh
shasum -a 256 DevCommand.dmg
```

**c. Test locally before pushing:**
```sh
brew tap eno-dev/tap
brew install --cask devcommand
brew audit --cask --new devcommand      # style + download checks
brew uninstall --cask devcommand
```

**d. Publish.** Commit + push the tap repo. Users then install with:
```sh
brew install --cask eno-dev/tap/devcommand
```

**Each future release:** bump `version` + `sha256` in `Casks/devcommand.rb` and push the tap — users
get it via `brew upgrade`.

Notes:
- Homebrew expects the app to be **signed + notarized** (steps 1–3) — another reason that comes first.
- A cask install has no source checkout, so DevCommand's in-app **Check for Updates** opens the Releases
  page rather than `git pull`-ing; cask users upgrade via `brew upgrade`. Both paths are fine.
- Once DevCommand has traction, graduate to the official `homebrew-cask` with `brew bump-cask-pr`.

## 6. Automating with CI (optional)
A GitHub Actions workflow triggered on `v*` tags can build → sign → notarize → staple → create the
release → bump the tap automatically. Store as repo secrets:
- the Developer ID cert as a base64-encoded `.p12` + its password,
- notary credentials (an App Store Connect API key `.p8`, key id, issuer id),
- a personal-access token with write access to the `homebrew-tap` repo.

Worth setting up once you're cutting releases regularly.

## Per-release checklist
1. [ ] Move CHANGELOG `[Unreleased]` → `[x.y.z]`; bump version in `scripts/bundle-app.sh`
2. [ ] `bundle-app.sh` → `codesign` (Developer ID, hardened runtime, entitlements)
3. [ ] `.dmg` → `notarytool submit --wait` → `stapler staple` → `spctl` check
4. [ ] `git tag` + `gh release create` with the `.dmg`
5. [ ] Bump `version` + `sha256` in the Homebrew tap, push
6. [ ] `brew upgrade --cask devcommand` on a clean machine to smoke-test
