import Foundation

/// Surfaces the user's shell setup so it's obvious which Node a launched command will use,
/// and which config file to edit when it's wrong. Probes through a *login* zsh so it matches
/// exactly what `Launch.inTerminal` (`#!/bin/zsh -l`) sees — Doctor and Run stay in agreement.
enum ShellEnvService {
    struct Info: Equatable {
        var managers: [String]      // detected version managers: fnm, nvm, volta, mise, asdf…
        var nodeVersion: String?    // e.g. "v20.11.1"
        var nodePath: String?       // e.g. "/Users/me/.local/state/fnm_multishells/…/bin/node"
        var configFiles: [String]   // shell rc files that actually exist: .zshrc, .zprofile, .zshenv

        var hasNode: Bool { nodeVersion != nil }
        var managerSummary: String { managers.isEmpty ? "system Node" : managers.joined(separator: " · ") }
    }

    static var zshrcPath: String { (NSHomeDirectory() as NSString).appendingPathComponent(".zshrc") }

    static func load() async -> Info {
        // One login-shell probe: print node's path + version, then any version managers on PATH.
        // nvm is a shell function (not a binary), so we also check for its install dir.
        let probe = """
        echo "NODE:$(command -v node 2>/dev/null)"
        echo "VER:$(node -v 2>/dev/null)"
        for m in fnm nvm volta mise asdf nodenv n; do command -v "$m" >/dev/null 2>&1 && echo "MGR:$m"; done
        [ -d "$HOME/.nvm" ] && echo "MGR:nvm"
        """
        let result = await Shell.zsh(probe)

        var nodePath: String?
        var nodeVersion: String?
        var managers: [String] = []
        for line in result.stdout.split(separator: "\n") {
            if line.hasPrefix("NODE:") {
                let value = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { nodePath = value }
            } else if line.hasPrefix("VER:") {
                let value = String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { nodeVersion = value }
            } else if line.hasPrefix("MGR:") {
                let value = String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                if !value.isEmpty, !managers.contains(value) { managers.append(value) }
            }
        }

        let fm = FileManager.default
        let home = NSHomeDirectory() as NSString
        let configFiles = [".zshrc", ".zprofile", ".zshenv"]
            .filter { fm.fileExists(atPath: home.appendingPathComponent($0)) }

        return Info(managers: managers, nodeVersion: nodeVersion, nodePath: nodePath, configFiles: configFiles)
    }

    /// Read `~/.zshrc` for the inline viewer, capped so a huge file can't bloat the popover.
    static func readZshrc(maxBytes: Int = 64_000) -> String? {
        guard let data = FileManager.default.contents(atPath: zshrcPath) else { return nil }
        var text = String(decoding: data.prefix(maxBytes), as: UTF8.self)
        if data.count > maxBytes { text += "\n\n… (truncated)" }
        return text
    }
}
