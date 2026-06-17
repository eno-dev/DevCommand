import AppKit

struct EditorApp: Identifiable, Hashable {
    let id: String      // full path to the .app
    let name: String    // display name, used with `open -a`
}

/// Discovers installed code editors / IDEs and their icons for the editor picker.
enum EditorApps {
    private static let candidates = [
        "Cursor", "Visual Studio Code", "VSCodium", "Windsurf", "Zed",
        "Sublime Text", "Nova", "Xcode", "Fleet", "BBEdit", "TextMate",
        "WebStorm", "PhpStorm", "PyCharm", "IntelliJ IDEA", "Android Studio"
    ]

    static func installed() -> [EditorApp] {
        InstalledApps.find(candidates).map { EditorApp(id: $0.path, name: $0.name) }
    }

    static func path(forName name: String) -> String? {
        InstalledApps.path(forName: name)
    }

    static func icon(forName name: String, size: CGFloat = 16) -> NSImage {
        InstalledApps.icon(forName: name, size: size)
    }
}
