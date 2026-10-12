# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Type to filter** in Ports and Projects. The field is focused when the panel opens, so you
  just start typing; Esc clears it.
- **Keyboard shortcuts** inside the popover: ⌘1 to ⌘5 switch panels, ⌘R refreshes, Esc closes.
- **Restart** a running dev server from its row. Metro and Expo also get "Restart & Clear Cache".
- **Simulator actions**: copy UDID, open a URL or deep link, toggle dark mode, and erase all
  content and settings (with confirmation).
- **More tools**: URL encode / decode, SHA-256, JSON pretty-print, and a converter that turns a
  pasted Unix timestamp into a date.
- Copying from the Ports menu confirms with a brief toast.

### Changed
- DevCommand reopens on the panel you used last, and the Ports "Hide system" choice sticks.
- The Projects list rescans by itself when you add or remove a dev folder in Settings.

### Fixed
- Simulators no longer show up under "Physical Devices" (newer Xcode versions report them
  there), which also scrambled the simulator list below.
- After closing the popover with the gear button, the menu-bar icon needed two clicks to reopen it.

## [0.2.0] - 2026-10-11

### Added
- **Privacy: "Show public IP" toggle** (Settings → Privacy, off by default). Out of the box
  DevCommand makes no outbound network requests at all; reveal your IP on demand by clicking the
  Public chip in the strip, or turn the setting on to always show it. The lookup is a single DNS
  query via `dig` (OpenDNS) with one HTTPS fallback, fetched on demand and never on a timer.
- **Favorite projects** — star a project to pin it to the top of the list; drag favorites to
  reorder. Non-favorites now sort running-first, then alphabetically.
- **Frictionless update & uninstall** — Settings → Check for Updates pulls + rebuilds in place
  (source installs), and Uninstall DevCommand trashes the app, prefs and login item in one click.
  Also `scripts/update.sh` and `scripts/uninstall.sh`.
- **Multiple dev folders** — scan more than one projects folder; add/remove them in Settings →
  Dev folders (or the + in the Projects header). Migrates the previous single folder automatically.
- **Show / hide a project's terminal** — running projects get a window button (and menu items) to
  bring their terminal to the front or minimise it. DevCommand titles each window "DevCommand • <project>"
  so it's easy to spot; precise window control on Terminal.app and iTerm.
- **Pick your terminal** — Settings → General → Terminal chooses which terminal app commands
  launch in (Terminal, iTerm, Warp, Ghostty, WezTerm, Alacritty, kitty, Hyper…); defaults to Terminal.
- **Run any package.json script** — projects expose a "Run script" submenu (build, preview,
  lint, test, typecheck, storybook…), each launched with the project's package manager.
- **Open in browser** on running dev servers (Bundlers panel), and a live **running badge**
  on projects showing the dev-server port with one-click open.
- **Clean build caches** per project — clears `.next` / `.nuxt` / `.vite` / `.turbo` /
  `.svelte-kit` / `dist` / `build` / `node_modules/.cache` and friends.
- **Shell panel** at the top of Doctor — shows the active Node version and version manager
  (nvm / fnm / volta / mise / asdf), the resolved `node` path, and which shell rc files exist;
  view `~/.zshrc` inline and open it in your editor / Terminal / Finder.
- **Open in Terminal** and **Install dependencies** actions on projects.
- Package-manager awareness — yarn / pnpm / bun projects are detected from the lockfile and
  shelled out to with the right runner instead of always `npm` / `npx`.
- QR codes for Metro/Expo servers offer an **Expo / Browser** toggle, encoding `exp://` so a
  scan opens the Expo Go / dev-client app instead of Safari.
- Inline error banners — failed actions (kill port, boot/stop simulator, stop bundler) now
  report why instead of failing silently.
- Unit tests for the parsers and command builders; CI now runs `swift test`.

### Changed
- **Terminal launches use AppleScript** (`do script` / `write text`) for Terminal and iTerm — no
  more macOS "OK to run this script?" prompt, and the command runs in an interactive login shell so
  `~/.zshrc` (nvm / fnm / volta / mise / asdf) is sourced. Other terminals keep the throwaway
  `.command` fallback, now with the quarantine flag stripped.
- **Merged the Bundlers panel into Projects.** Each project now starts/stops its own dev server
  inline (Start → running `:port` + open + QR + Stop), and a "Other running servers" section
  lists any server not tied to a scanned project. Removes the duplicate start/stop surface.
- Launched Terminal commands run under a **login shell** (`#!/bin/zsh -l`) so Node version
  managers initialise — fixes `node`/`npx` not found (or wrong version) for bundled launches.
- Bundler detection also recognises `bun` and `deno` dev servers.
- Panels redraw only when a poll finds something new, not on every 4-second tick.
- Doctor reuses its tool-version probe for 5 minutes, so reopening it no longer boots node and
  ruby each time. Re-check still runs a fresh one.
- Release builds are stripped of local symbols, taking the executable from about 3 MB to about
  1 MB.

### Fixed
- Loopback-only ports (e.g. `127.0.0.1`) no longer offer an unreachable LAN URL / QR code.
- Base64 decoder now accepts URL-safe and unpadded input.
- The Settings version now reads from the app bundle instead of a hard-coded string.
- A subprocess that fails to launch no longer leaks its pipe descriptors (each failure used to
  hold two open for good).
- The fallback `.command` launcher deletes itself once it starts instead of piling up in the temp
  folder.

## [0.1.0] - 2026-06-11

Initial release.

### Added
- Menu-bar app (SwiftUI `MenuBarExtra`, `LSUIElement`, ~1 MB, no Dock icon).
- **Ports** panel — list listening TCP ports with owning process, dev-port labels, per-row
  actions menu (open in browser, copy URL / LAN URL / PID, terminate, force-kill), system/editor
  noise hidden by default.
- **Sims** panel — iOS + tvOS simulators grouped by runtime; boot / shutdown / open Simulator;
  run a project on a chosen simulator.
- **Bundlers** panel — live Metro/Expo servers discovered from ports and resolved to their
  project directory; start (with optional cache clear) and stop.
- **Projects** panel — scans a dev folder, classifies projects, per-project Run iOS / Run tvOS /
  Prebuild / Pod install / open in Xcode, editor, Finder.
- **Tools** panel — UUID, Unix timestamp, secret token, Base64, JWT decode, and one-tap
  maintenance (clear DerivedData, reset Watchman, clean npm cache, kill node).
- Always-on **IP bar** (LAN + public IP, click to copy).
- **QR codes** on Ports and Bundler rows to open a dev server on a physical device.
- **Settings** window — toggle panels and tools, set dev folder + editor, launch at login.
- Amber design system, tooltips on all controls, and polling that pauses while the panel is hidden.

[Unreleased]: https://github.com/eno-dev/DevCommand/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/eno-dev/DevCommand/releases/tag/v0.2.0
[0.1.0]: https://github.com/eno-dev/DevCommand/releases/tag/v0.1.0
