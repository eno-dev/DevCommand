import Foundation

enum SimulatorService {
    static func list() async -> [SimRuntimeGroup] {
        let result = await Shell.run("/usr/bin/xcrun",
                                     ["simctl", "list", "devices", "available", "--json"])
        return parse(result.stdout)
    }

    // MARK: Parsing

    private struct SimctlList: Decodable {
        let devices: [String: [DeviceDTO]]
    }
    private struct DeviceDTO: Decodable {
        let udid: String
        let name: String
        let state: String
        let isAvailable: Bool?
    }

    static func parse(_ json: String) -> [SimRuntimeGroup] {
        guard let data = json.data(using: .utf8),
              let root = try? JSONDecoder().decode(SimctlList.self, from: data) else { return [] }

        var groups: [SimRuntimeGroup] = []
        for (key, devices) in root.devices {
            let available = devices.filter { $0.isAvailable != false }
            guard !available.isEmpty else { continue }
            let (platform, version) = runtimeInfo(key)
            let sims = available
                .map { Simulator(udid: $0.udid, name: $0.name, state: $0.state, runtimeKey: key) }
                .sorted { ($0.isBooted ? 0 : 1, $0.name) < ($1.isBooted ? 0 : 1, $1.name) }
            groups.append(SimRuntimeGroup(platform: platform, version: version, devices: sims))
        }

        return groups.sorted { lhs, rhs in
            let lp = platformRank(lhs.platform), rp = platformRank(rhs.platform)
            if lp != rp { return lp < rp }
            return lhs.version.compare(rhs.version, options: .numeric) == .orderedDescending
        }
    }

    /// "com.apple.CoreSimulator.SimRuntime.iOS-26-5" -> ("iOS", "26.5")
    private static func runtimeInfo(_ key: String) -> (platform: String, version: String) {
        let tail = key.replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: "")
        let parts = tail.split(separator: "-")
        let platform = parts.first.map(String.init) ?? tail
        let version = parts.dropFirst().joined(separator: ".")
        return (platform, version)
    }

    private static func platformRank(_ platform: String) -> Int {
        switch platform {
        case "iOS": return 0
        case "tvOS": return 1
        case "watchOS": return 2
        case "xrOS": return 3
        default: return 9
        }
    }

    // MARK: Actions

    @discardableResult
    static func boot(_ udid: String) async -> ShellResult {
        await Shell.run("/usr/bin/xcrun", ["simctl", "boot", udid])
    }

    @discardableResult
    static func shutdown(_ udid: String) async -> ShellResult {
        await Shell.run("/usr/bin/xcrun", ["simctl", "shutdown", udid])
    }

    static func openSimulatorApp() async {
        _ = await Shell.run("/usr/bin/open", ["-a", "Simulator"])
    }

    /// Bundle ids of the user's (non-Apple) apps currently running on a booted simulator.
    /// Reads `launchctl list` inside the sim; each running app shows as `UIKitApplication:<id>[…]`.
    static func runningApps(udid: String) async -> [String] {
        let result = await Shell.run("/usr/bin/xcrun", ["simctl", "spawn", udid, "launchctl", "list"])
        var ids: [String] = []
        for line in result.stdout.split(separator: "\n") {
            guard let marker = line.range(of: "UIKitApplication:") else { continue }
            let bid = String(line[marker.upperBound...].prefix { $0 != "[" })
            if !bid.isEmpty && !bid.hasPrefix("com.apple.") { ids.append(bid) }
        }
        return ids
    }

    /// Reload an app by restarting it on the simulator: terminate, then relaunch.
    /// A relaunched dev build re-fetches its JS bundle from Metro, so this acts as a
    /// reliable reload without keystrokes or Accessibility permission.
    static func reloadApp(udid: String, bundleID: String) async {
        _ = await Shell.run("/usr/bin/xcrun", ["simctl", "terminate", udid, bundleID])
        _ = await Shell.run("/usr/bin/xcrun", ["simctl", "launch", udid, bundleID])
    }
}
