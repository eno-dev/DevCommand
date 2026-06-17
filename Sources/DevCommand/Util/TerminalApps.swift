import AppKit

struct TerminalApp: Identifiable, Hashable {
    let id: String      // full path to the .app
    let name: String    // display name, used with `open -a`
}

/// Discovers installed terminal emulators and their icons for the terminal picker.
/// `open -a <name>` resolves by name via LaunchServices, so launching works even for a
/// terminal in a non-standard location — the path is only needed for the icon.
enum TerminalApps {
    private static let candidates = [
        "Terminal", "iTerm", "Warp", "Ghostty", "WezTerm",
        "Alacritty", "kitty", "Hyper", "Tabby", "Rio"
    ]

    static func installed() -> [TerminalApp] {
        InstalledApps.find(candidates).map { TerminalApp(id: $0.path, name: $0.name) }
    }

    static func path(forName name: String) -> String? {
        InstalledApps.path(forName: name)
    }

    static func icon(forName name: String, size: CGFloat = 16) -> NSImage {
        InstalledApps.icon(forName: name, size: size)
    }
}
