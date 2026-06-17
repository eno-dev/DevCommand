import Foundation

enum ProjectKind: String, Hashable {
    case expo = "Expo"
    case reactNative = "React Native"
    case nativeApple = "iOS / tvOS"
    case web = "Web / Node"

    var icon: String {
        switch self {
        case .expo: return "apps.iphone"
        case .reactNative: return "atom"
        case .nativeApple: return "applelogo"
        case .web: return "globe"
        }
    }
}

struct DevProject: Identifiable, Hashable {
    let name: String
    let path: String
    let kind: ProjectKind
    let hasIOS: Bool        // can build/run on an Apple simulator
    let hasPods: Bool       // ios/Podfile present
    let supportsTV: Bool    // react-native-tvos detected
    let framework: String?  // web framework label (Vite / Next.js / …), nil for native/RN
    let devScript: String?  // package.json script that starts the dev server
    let bundleID: String?   // iOS bundle identifier, used to detect the app running on a sim
    let packageManager: PackageManager  // npm / yarn / pnpm / bun, from the lockfile
    let scripts: [String]               // package.json script names, dev-first ordered

    var id: String { path }
    var isJavaScript: Bool { kind == .expo || kind == .reactNative || kind == .web }
    var usesMetro: Bool { kind == .expo || kind == .reactNative }  // supports JS reload / cache reset
    var kindLabel: String { framework ?? kind.rawValue }
}
