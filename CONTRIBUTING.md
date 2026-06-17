# Contributing to DevCommand

Thanks for taking the time to contribute! DevCommand is a small, dependency-free SwiftUI
menu-bar app, so getting started is quick.

## Prerequisites

- macOS 14 or later
- Xcode 16+ (for the bundled Swift 6 toolchain)

## Build & run

```sh
swift build            # debug build
swift run              # run from the CLI — the menu-bar icon appears
```

Or open the folder in Xcode (`File ▸ Open`) and press ⌘R. To produce an installable bundle:

```sh
zsh scripts/install.sh   # build (release) → DevCommand.app → /Applications → launch
```

## Project layout

```
Sources/DevCommand/
  DevCommandApp.swift      @main, MenuBarExtra + Settings scenes
  Theme.swift           design tokens + reusable components
  Shell.swift           Process wrapper everything shells out through
  Models/               Port, Simulator, DevProject, Bundler, DevTool, HealthCheck, PackageManager, PhysicalDevice
  Services/             PortService, SimulatorService, ProjectService, BundlerService, DeviceService, DoctorService, ShellEnvService, ToolsService, NetworkService
  Views/                one file per panel + RootView, NetworkBar, SettingsView, QRCodeView
  Util/                 Launch (terminal/open), LoginItem (launch-at-login), EditorApps / TerminalApps / InstalledApps (app discovery)
```

## Conventions

- **No third-party dependencies.** DevCommand stays light — SwiftUI / AppKit / Foundation only.
- **Shell out through `Shell`**, never `Process` directly, so PATH resolution and pipe handling stay consistent.
- **Poll only while visible** — gate timers on `controlActiveState` (see `PortsView`).
- Match the surrounding style: design tokens from `Theme`, `Pill` / `SectionLabel` / `StatusDot`
  for UI, `Theme.mono(...)` for numbers.
- Render integers with `Text(verbatim:)` so they don't pick up locale thousands separators.

## Pull requests

1. Fork and branch from `main`.
2. Keep changes focused; one concern per PR.
3. Make sure `swift build` is clean (CI runs it on every push).
4. Describe what you changed and how you tested it.

By submitting a PR you agree your contribution is licensed under the project's [MIT license](LICENSE).

## Releasing

Maintainers — the full signed-build → notarize → GitHub Release → Homebrew cask runbook lives in
[docs/RELEASING.md](docs/RELEASING.md).
