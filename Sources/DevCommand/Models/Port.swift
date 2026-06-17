import Foundation

struct ListeningPort: Identifiable, Hashable {
    let port: Int
    let pid: Int
    let command: String
    let user: String
    let address: String   // "*", "127.0.0.1", "::1", ...

    var id: String { "\(pid):\(port)" }

    var isLoopback: Bool { address == "127.0.0.1" || address == "::1" }
    var isSystem: Bool { PortCatalog.systemCommands.contains(command) }
    /// Editor/Electron helper processes (Cursor, VS Code, …) — noise, not dev servers.
    var isAppHelper: Bool {
        let name = command.lowercased()
        return name.contains("helper") || name.hasPrefix("cursor") || name.contains("electron")
    }
    var devLabel: String? { PortCatalog.devLabel(forPort: port) }
    /// Storybook's dev server (6006, or 6007 when the default is taken).
    var isStorybook: Bool { port == 6006 || port == 6007 }
    /// A Metro/Expo port the Expo Go / dev-client app can open via the `exp://` scheme.
    var supportsExpoScheme: Bool {
        switch port {
        case 8081, 8082, 19000, 19001, 19006: return true
        default: return false
        }
    }
    var isDev: Bool {
        devLabel != nil || PortCatalog.devCommands.contains { command.lowercased().contains($0) }
    }
}

enum PortCatalog {
    /// Background/system daemons that usually aren't interesting to a developer.
    static let systemCommands: Set<String> = [
        "rapportd", "ControlCe", "ControlCenter", "sharingd", "remoted",
        "launchd", "cloudd", "apsd", "identitys", "nsurlsessiond", "mDNSResponder"
    ]

    /// Substrings that mark a process as a dev tool worth surfacing first.
    static let devCommands: [String] = [
        "node", "expo", "metro", "vite", "next", "deno", "bun",
        "ruby", "rails", "python", "php", "java", "gradle",
        "postgres", "mongod", "redis", "docker", "watchman"
    ]

    /// Friendly label for well-known development ports.
    static func devLabel(forPort port: Int) -> String? {
        switch port {
        case 8081: return "Metro"
        case 8082: return "Metro alt"
        case 19000: return "Expo"
        case 19001: return "Expo Dev"
        case 19002: return "Expo Tunnel"
        case 19006: return "Expo Web"
        case 8080: return "Dev server"
        case 8097: return "RN DevTools"
        case 5173: return "Vite"
        case 6006, 6007: return "Storybook"
        case 4321: return "Astro"
        case 3000: return "Node / Next"
        case 3001: return "Node alt"
        case 4000: return "Dev server"
        case 9229: return "Node debug"
        case 5432: return "Postgres"
        case 27017: return "MongoDB"
        case 6379: return "Redis"
        case 5000, 7000: return "AirPlay"
        default: return nil
        }
    }
}
