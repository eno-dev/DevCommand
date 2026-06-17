import Foundation

/// Lightweight persisted settings backed by UserDefaults.
enum Preferences {
    private static let devRootKey = "devRoot"        // legacy single folder, migrated into devRoots
    private static let devRootsKey = "devRoots"
    private static let editorKey = "editorApp"
    private static let terminalKey = "terminalApp"
    private static let showPublicIPKey = "showPublicIP"
    private static let favoritesKey = "favoriteProjects"
    private static let sourceRepoKey = "sourceRepo"

    /// Folders scanned for projects (default: [~/Dev]). Order preserved, duplicates dropped.
    static var devRoots: [String] {
        get {
            if let arr = UserDefaults.standard.stringArray(forKey: devRootsKey), !arr.isEmpty { return arr }
            if let legacy = UserDefaults.standard.string(forKey: devRootKey), !legacy.isEmpty { return [legacy] }
            return [defaultDevRoot]
        }
        set {
            var seen = Set<String>(), cleaned: [String] = []
            for path in newValue where !seen.contains(path) { seen.insert(path); cleaned.append(path) }
            UserDefaults.standard.set(cleaned, forKey: devRootsKey)
        }
    }

    /// Primary (first) dev folder — convenience for single-root contexts.
    static var devRoot: String { devRoots.first ?? defaultDevRoot }

    static var defaultDevRoot: String {
        (NSHomeDirectory() as NSString).appendingPathComponent("Dev")
    }

    /// Editor app name used by "Open in editor" (default: Cursor).
    static var editorApp: String {
        get { UserDefaults.standard.string(forKey: editorKey) ?? "Cursor" }
        set { UserDefaults.standard.set(newValue, forKey: editorKey) }
    }

    /// Terminal app that commands launch in (default: Terminal).
    static var terminalApp: String {
        get { UserDefaults.standard.string(forKey: terminalKey) ?? "Terminal" }
        set { UserDefaults.standard.set(newValue, forKey: terminalKey) }
    }

    /// Whether the menu-bar strip looks up and shows your public IP. Off by default, so DevCommand
    /// makes no outbound request for it until you turn this on or tap "Show" in the strip.
    static var showPublicIP: Bool {
        get { UserDefaults.standard.object(forKey: showPublicIPKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: showPublicIPKey) }
    }

    /// Favorited project paths, in display order (pinned to the top of the Projects list).
    static var favoriteProjects: [String] {
        get { UserDefaults.standard.stringArray(forKey: favoritesKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: favoritesKey) }
    }

    /// Absolute path of the source checkout DevCommand was built from — written by `install.sh`
    /// so the in-app "Update" can `git pull` + rebuild in place. nil for non-source installs.
    static var sourceRepo: String? {
        get { UserDefaults.standard.string(forKey: sourceRepoKey) }
        set { UserDefaults.standard.set(newValue, forKey: sourceRepoKey) }
    }
}
