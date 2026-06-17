import Foundation

enum DevToolCategory: String, Hashable {
    case generate = "Generate"
    case convert = "Convert"
    case maintain = "Maintenance"
}

/// Small, reach-for utilities surfaced in the Tools panel.
enum DevTool: String, CaseIterable, Identifiable {
    case uuid, timestamp, secret        // generate
    case base64, jwt                    // convert
    case derivedData, watchman, npmCache, killNode   // maintenance

    var id: String { rawValue }

    var category: DevToolCategory {
        switch self {
        case .uuid, .timestamp, .secret: return .generate
        case .base64, .jwt: return .convert
        case .derivedData, .watchman, .npmCache, .killNode: return .maintain
        }
    }

    var title: String {
        switch self {
        case .uuid: return "UUID v4"
        case .timestamp: return "Unix timestamp"
        case .secret: return "Secret token"
        case .base64: return "Base64"
        case .jwt: return "JWT decode"
        case .derivedData: return "Clear DerivedData"
        case .watchman: return "Reset Watchman"
        case .npmCache: return "Clean npm cache"
        case .killNode: return "Kill all node"
        }
    }

    var subtitle: String {
        switch self {
        case .uuid: return "Generate & copy a v4 UUID"
        case .timestamp: return "Current epoch — seconds / ms"
        case .secret: return "32 random bytes, base64 (JWT secrets, keys)"
        case .base64: return "Encode / decode text"
        case .jwt: return "Header + payload (no signature check)"
        case .derivedData: return "rm -rf ~/…/Xcode/DerivedData"
        case .watchman: return "watchman watch-del-all"
        case .npmCache: return "npm cache clean --force"
        case .killNode: return "pkill -x node"
        }
    }

    var icon: String {
        switch self {
        case .uuid: return "number"
        case .timestamp: return "clock"
        case .secret: return "key.horizontal"
        case .base64: return "textformat"
        case .jwt: return "rectangle.split.3x1"
        case .derivedData: return "trash"
        case .watchman: return "eye.trianglebadge.exclamationmark"
        case .npmCache: return "shippingbox"
        case .killNode: return "xmark.octagon"
        }
    }

    var isDestructive: Bool { self == .derivedData || self == .killNode }
}
