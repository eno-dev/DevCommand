import Foundation

/// Runs a set of environment health checks for the Doctor panel. The version/presence probes
/// run in ONE login shell (not one each), the slow DerivedData `du` is cached, and the rest
/// run concurrently — so reopening Doctor is cheap.
enum DoctorService {
    /// Caches the (slow) DerivedData size so reopening Doctor within the TTL is instant.
    private static let derivedSizeCache = TimedValueCache<String>()

    static func runAll() async -> [HealthCheck] {
        async let probe = batchedProbe()
        async let derived = derivedData()
        async let servers = devServers()

        let fields = await probe
        return [
            versionCheck(fields, key: "node", id: "node", title: "Node.js", missing: .fail, install: "brew install node"),
            versionCheck(fields, key: "npm", id: "npm", title: "npm", missing: .fail, install: "brew install node"),
            presenceCheck(fields, key: "watchman", id: "watchman", title: "Watchman", missing: .warn, install: "brew install watchman"),
            versionCheck(fields, key: "pod", id: "pod", title: "CocoaPods", missing: .warn, install: "sudo gem install cocoapods"),
            versionCheck(fields, key: "git", id: "git", title: "Git", missing: .warn, install: "xcode-select --install"),
            xcodeCheck(fields),
            await derived,
            await servers,
        ]
    }

    /// One login shell probes every tool, line-tagged `key:value`, instead of 6 separate spawns.
    private static func batchedProbe() async -> [String: String] {
        let script = """
        echo "node:$(node -v 2>/dev/null)"
        echo "npm:$(npm -v 2>/dev/null)"
        echo "git:$(git --version 2>/dev/null)"
        echo "pod:$(pod --version 2>/dev/null)"
        echo "watchman:$(command -v watchman 2>/dev/null)"
        echo "xcode:$(xcode-select -p 2>/dev/null)"
        """
        let result = await Shell.zsh(script)
        return parseProbe(result.stdout)
    }

    // MARK: Pure parsing / check building (unit-tested)

    /// Parse the line-tagged probe output into `[key: value]` (split on the first colon).
    static func parseProbe(_ output: String) -> [String: String] {
        var fields: [String: String] = [:]
        for line in output.split(separator: "\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if !key.isEmpty { fields[key] = value }
        }
        return fields
    }

    /// A tool reporting its version (e.g. `node -v`): present → ok with the version, else missing.
    static func versionCheck(_ fields: [String: String], key: String, id: String, title: String,
                             missing: HealthCheck.Status, install: String?) -> HealthCheck {
        let value = fields[key] ?? ""
        if !value.isEmpty {
            let line = value.split(separator: "\n").first.map(String.init) ?? value
            return HealthCheck(id: id, title: title, detail: line, status: .ok)
        }
        return HealthCheck(id: id, title: title, detail: "Not installed", status: missing,
                           fixLabel: install != nil ? "Install" : nil, fixCommand: install)
    }

    /// A tool we only check for presence (a `command -v` path): present → ok, else missing.
    static func presenceCheck(_ fields: [String: String], key: String, id: String, title: String,
                              missing: HealthCheck.Status, install: String?) -> HealthCheck {
        if !(fields[key] ?? "").isEmpty {
            return HealthCheck(id: id, title: title, detail: "Installed", status: .ok)
        }
        return HealthCheck(id: id, title: title, detail: "Not installed", status: missing,
                           fixLabel: install != nil ? "Install" : nil, fixCommand: install)
    }

    static func xcodeCheck(_ fields: [String: String]) -> HealthCheck {
        let path = fields["xcode"] ?? ""
        if !path.isEmpty {
            return HealthCheck(id: "xcode", title: "Xcode tools", detail: path, status: .ok)
        }
        return HealthCheck(id: "xcode", title: "Xcode tools", detail: "Command-line tools not selected",
                           status: .warn, fixLabel: "Install", fixCommand: "xcode-select --install")
    }

    /// True when a `du -sh` size string looks large enough to warn about (≥ 5 GB, or any TB).
    static func isLarge(_ size: String) -> Bool {
        if size.hasSuffix("T") { return true }
        if size.hasSuffix("G"), let n = Double(size.dropLast()) { return n >= 5 }
        return false
    }

    // MARK: Shell-backed checks

    private static func derivedData() async -> HealthCheck {
        let path = "~/Library/Developer/Xcode/DerivedData"
        // Cached 2 min; concurrent Doctor refreshes coalesce onto a single `du`.
        let size = await derivedSizeCache.value(ttl: 120) {
            let result = await Shell.zsh("du -sh \(path) 2>/dev/null | cut -f1")
            let s = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            return s.isEmpty ? nil : s
        } ?? ""
        guard !size.isEmpty else {
            return HealthCheck(id: "derived", title: "DerivedData", detail: "Empty", status: .ok)
        }
        return HealthCheck(id: "derived", title: "DerivedData", detail: size,
                           status: isLarge(size) ? .warn : .ok,
                           fixLabel: "Clear", fixCommand: "rm -rf \(path)/* && echo cleared")
    }

    private static func devServers() async -> HealthCheck {
        let active = await BundlerService.active()
        let detail = active.isEmpty ? "None" : "\(active.count) · " + active.map { "\($0.port)" }.joined(separator: " ")
        return HealthCheck(id: "servers", title: "Dev servers running", detail: detail, status: .ok)
    }
}
