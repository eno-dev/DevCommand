import Foundation

/// The JavaScript package manager a project uses, inferred from its lockfile.
/// Drives which runner verb we put in front of `expo` / `react-native` / dev scripts,
/// so a yarn/pnpm/bun project isn't shelled out to with `npm`.
enum PackageManager: String, Hashable {
    case npm, yarn, pnpm, bun

    /// Run a `package.json` script — e.g. `npm run dev`, `yarn dev`, `pnpm dev`, `bun run dev`.
    var run: String {
        switch self {
        case .npm: return "npm run"
        case .yarn: return "yarn"
        case .pnpm: return "pnpm"
        case .bun: return "bun run"
        }
    }

    /// Execute a binary from the project / registry (npx-style) — e.g. `npx`, `yarn`, `pnpm`, `bunx`.
    var exec: String {
        switch self {
        case .npm: return "npx"
        case .yarn: return "yarn"
        case .pnpm: return "pnpm"
        case .bun: return "bunx"
        }
    }

    /// Install all dependencies.
    var install: String {
        switch self {
        case .npm: return "npm install"
        case .yarn: return "yarn"
        case .pnpm: return "pnpm install"
        case .bun: return "bun install"
        }
    }

    var label: String { rawValue }

    /// Detect from a project's lockfile. Order matters: a repo can carry more than one,
    /// so we prefer the most specific (bun → pnpm → yarn), falling back to npm.
    static func detect(at path: String, fm: FileManager) -> PackageManager {
        let ns = path as NSString
        if fm.fileExists(atPath: ns.appendingPathComponent("bun.lockb")) ||
           fm.fileExists(atPath: ns.appendingPathComponent("bun.lock")) { return .bun }
        if fm.fileExists(atPath: ns.appendingPathComponent("pnpm-lock.yaml")) { return .pnpm }
        if fm.fileExists(atPath: ns.appendingPathComponent("yarn.lock")) { return .yarn }
        return .npm
    }
}
