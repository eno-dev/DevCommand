import Foundation

/// A live dev server (Metro/Expo) inferred from a listening port + its owning process.
struct ActiveBundler: Identifiable, Hashable {
    let pid: Int
    let port: Int
    let cwd: String
    let projectName: String

    var id: Int { pid }
    var label: String { PortCatalog.devLabel(forPort: port) ?? "Bundler" }
    /// A Metro/Expo port the Expo Go / dev-client app can open via the `exp://` scheme.
    var supportsExpoScheme: Bool {
        switch port {
        case 8081, 8082, 19000, 19001, 19006: return true
        default: return false
        }
    }
}
