import Foundation

struct Simulator: Identifiable, Hashable {
    let udid: String
    let name: String
    let state: String       // "Booted", "Shutdown", ...
    let runtimeKey: String

    var id: String { udid }
    var isBooted: Bool { state == "Booted" }
    var isTV: Bool { runtimeKey.contains("tvOS") }
}

struct SimRuntimeGroup: Identifiable, Hashable {
    let platform: String    // "iOS", "tvOS", ...
    let version: String     // "26.5"
    let devices: [Simulator]

    var id: String { "\(platform) \(version)" }
}
