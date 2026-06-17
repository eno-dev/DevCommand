import AppKit
import UniformTypeIdentifiers

/// Shared discovery for installed `.app`s by display name — used by the editor and terminal
/// pickers so they don't each reimplement the filesystem scan + icon rendering.
enum InstalledApps {
    /// Where third-party and system apps live. `/System/Applications/Utilities` matters for
    /// Terminal.app, which Apple ships there (not in `/Applications`).
    static let searchDirs = [
        "/Applications",
        (NSHomeDirectory() as NSString).appendingPathComponent("Applications"),
        "/Applications/Utilities",
        "/System/Applications/Utilities"
    ]

    /// `(name, path)` for each candidate that exists, in candidate order (first dir match wins).
    static func find(_ candidates: [String], in dirs: [String] = searchDirs) -> [(name: String, path: String)] {
        let fm = FileManager.default
        var found: [(String, String)] = []
        for name in candidates {
            for dir in dirs {
                let path = (dir as NSString).appendingPathComponent("\(name).app")
                if fm.fileExists(atPath: path) { found.append((name, path)); break }
            }
        }
        return found
    }

    static func path(forName name: String, in dirs: [String] = searchDirs) -> String? {
        let fm = FileManager.default
        for dir in dirs {
            let path = (dir as NSString).appendingPathComponent("\(name).app")
            if fm.fileExists(atPath: path) { return path }
        }
        return nil
    }

    /// A square icon for an app name, falling back to a generic app icon.
    static func icon(forName name: String, size: CGFloat = 16) -> NSImage {
        let source = path(forName: name).map { NSWorkspace.shared.icon(forFile: $0) }
            ?? NSWorkspace.shared.icon(for: .applicationBundle)
        let resized = NSImage(size: NSSize(width: size, height: size))
        resized.lockFocus()
        source.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        resized.unlockFocus()
        return resized
    }
}
