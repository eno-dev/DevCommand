import Foundation

/// On-demand update check against the project's GitHub releases. Nothing here runs on its own:
/// one request goes out when you click "Check for Updates", and none otherwise.
enum UpdateService {
    static let releasesPage = URL(string: "https://github.com/eno-dev/DevCommand/releases/latest")!
    private static let latestReleaseAPI =
        URL(string: "https://api.github.com/repos/eno-dev/DevCommand/releases/latest")!

    enum Outcome: Equatable {
        case upToDate            // the running version is the newest release (or newer)
        case available(String)   // a newer released version
        case failed              // offline, rate-limited, or an answer we couldn't read
    }

    /// The running app's marketing version, or nil when run without a bundle (`swift run`).
    static var currentVersion: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    static func check(current: String? = currentVersion) async -> Outcome {
        var request = URLRequest(url: latestReleaseAPI)
        request.timeoutInterval = 10
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // A one-shot ephemeral session: no cache or cookies written to disk, and nothing kept
        // alive once it is invalidated.
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let latest = latestVersion(fromReleaseJSON: data) else { return .failed }
        return isNewer(latest, than: current ?? "0") ? .available(latest) : .upToDate
    }

    // MARK: Pure parsing (unit-tested)

    /// The version in a GitHub "latest release" response: its `tag_name` without the leading `v`.
    /// Only a plain dotted number is accepted, since the string ends up in the UI.
    static func latestVersion(fromReleaseJSON data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = object["tag_name"] as? String else { return nil }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(parts.count),
              parts.allSatisfy({ !$0.isEmpty && $0.count <= 6 && $0.allSatisfy { $0.isASCII && $0.isNumber } })
        else { return nil }
        return version
    }

    /// Numeric, component-wise comparison: 0.10.0 is newer than 0.9.3, and 1.2 equals 1.2.0.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let lhs = components(candidate), rhs = components(current)
        for index in 0..<max(lhs.count, rhs.count) {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right { return left > right }
        }
        return false
    }

    private static func components(_ version: String) -> [Int] {
        version.split(separator: ".").map { Int($0) ?? 0 }
    }
}
