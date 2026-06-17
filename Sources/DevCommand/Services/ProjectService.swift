import Foundation

/// An Apple run target. For Expo these are the same `ios` project switched by `EXPO_TV`:
/// the tvOS variant builds against the tvOS SDK, the iOS variant against iphoneos.
enum ApplePlatform {
    case iOS, tvOS
    var isTV: Bool { self == .tvOS }
    var label: String { self == .tvOS ? "tvOS" : "iOS" }
}

/// The result of deciding how to run a project on a chosen platform, validated against the
/// native prebuild that currently exists in `ios/`.
enum RunOutcome {
    /// Good to go — launch this shell command (empty string ⇒ open Xcode instead).
    case command(String)
    /// The chosen device/simulator can't run this project as-is. Don't launch the doomed
    /// build; show `message`. `fix` is a ready command that makes it work (re-prebuild +
    /// run), or `nil` when there's no corrective command — e.g. the project can't target
    /// that platform at all.
    case platformMismatch(message: String, fix: String?)
}

/// A platform-mismatch surfaced to the user as a dialog: the full explanation plus, when one
/// exists, the corrective command the app can run on their behalf (prebuild + run).
struct RunMismatch: Identifiable {
    let id = UUID()
    let project: DevProject
    let message: String
    let fix: String?    // corrective command, or nil when nothing can fix it
}

enum ProjectService {
    static func scan(root: String) async -> [DevProject] {
        await scan(roots: [root])
    }

    /// Scan several dev folders, aggregate, drop duplicate paths, and sort by name.
    static func scan(roots: [String]) async -> [DevProject] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var all: [DevProject] = []
                var seen = Set<String>()
                for root in roots {
                    for project in scanSync(root: root) where !seen.contains(project.path) {
                        seen.insert(project.path)
                        all.append(project)
                    }
                }
                let sorted = all.sorted {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                continuation.resume(returning: sorted)
            }
        }
    }

    static func scanSync(root: String) -> [DevProject] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: root) else { return [] }

        var projects: [DevProject] = []
        for entry in entries where !entry.hasPrefix(".") {
            let path = (root as NSString).appendingPathComponent(entry)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { continue }
            if let project = classify(name: entry, path: path, fm: fm) {
                projects.append(project)
            }
        }
        return projects.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static func classify(name: String, path: String, fm: FileManager) -> DevProject? {
        let ns = path as NSString
        let hasPackageJSON = fm.fileExists(atPath: ns.appendingPathComponent("package.json"))
        let hasAppJSON = fm.fileExists(atPath: ns.appendingPathComponent("app.json"))
        let iosDir = ns.appendingPathComponent("ios")
        let hasIOSDir = fm.fileExists(atPath: iosDir)
        let hasPods = fm.fileExists(atPath: (iosDir as NSString).appendingPathComponent("Podfile"))
        let topXcode = firstXcode(in: path, fm: fm)

        var hasExpo = false, hasRN = false, supportsTV = false
        var detectedFramework: String?
        var devScript: String?
        var scriptNames: [String] = []
        if hasPackageJSON,
           let data = try? Data(contentsOf: URL(fileURLWithPath: ns.appendingPathComponent("package.json"))),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let deps = (obj["dependencies"] as? [String: Any]) ?? [:]
            let devDeps = (obj["devDependencies"] as? [String: Any]) ?? [:]
            let all = deps.merging(devDeps) { current, _ in current }
            let scripts = (obj["scripts"] as? [String: Any]) ?? [:]
            hasExpo = all["expo"] != nil
            hasRN = all["react-native"] != nil || all["react-native-tvos"] != nil
            supportsTV = all["react-native-tvos"] != nil
            detectedFramework = detectFramework(all)
            devScript = scripts["dev"] != nil ? "dev" : (scripts["start"] != nil ? "start" : nil)
            scriptNames = prioritizedScripts(Array(scripts.keys))
        }

        let kind: ProjectKind
        if hasExpo {
            kind = .expo
        } else if hasRN || hasAppJSON {
            kind = .reactNative
        } else if topXcode != nil || (hasIOSDir && !hasPackageJSON) {
            kind = .nativeApple
        } else if hasPackageJSON {
            kind = .web
        } else {
            return nil
        }

        let hasIOS = hasIOSDir || topXcode != nil
        let packageManager = hasPackageJSON ? PackageManager.detect(at: path, fm: fm) : .npm
        return DevProject(name: name, path: path, kind: kind,
                          hasIOS: hasIOS, hasPods: hasPods, supportsTV: supportsTV,
                          framework: kind == .web ? detectedFramework : nil,
                          devScript: devScript,
                          bundleID: hasIOS ? extractBundleID(path: path, fm: fm) : nil,
                          packageManager: packageManager,
                          scripts: scriptNames)
    }

    /// The project's iOS bundle id, from Expo's `app.json` or a native `project.pbxproj`.
    private static func extractBundleID(path: String, fm: FileManager) -> String? {
        let ns = path as NSString

        // Expo: expo.ios.bundleIdentifier (config may live under an "expo" key or at the top level).
        let appJSON = ns.appendingPathComponent("app.json")
        if let data = try? Data(contentsOf: URL(fileURLWithPath: appJSON)),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let root = (obj["expo"] as? [String: Any]) ?? obj
            if let ios = root["ios"] as? [String: Any], let bid = ios["bundleIdentifier"] as? String {
                return bid
            }
        }

        // Native / bare RN: first concrete PRODUCT_BUNDLE_IDENTIFIER in the Xcode project.
        let iosDir = ns.appendingPathComponent("ios")
        if let entries = try? fm.contentsOfDirectory(atPath: iosDir),
           let proj = entries.first(where: { $0.hasSuffix(".xcodeproj") }) {
            let pbx = ((iosDir as NSString).appendingPathComponent(proj) as NSString)
                .appendingPathComponent("project.pbxproj")
            if let text = try? String(contentsOfFile: pbx, encoding: .utf8) {
                for line in text.split(separator: "\n")
                where line.contains("PRODUCT_BUNDLE_IDENTIFIER") && !line.contains("Test") {
                    guard let eq = line.firstIndex(of: "=") else { continue }
                    let value = line[line.index(after: eq)...]
                        .trimmingCharacters(in: CharacterSet(charactersIn: "; \"\t"))
                    if !value.isEmpty && !value.contains("$(") { return value }  // skip build-var refs
                }
            }
        }
        return nil
    }

    /// First project whose bundle id matches one of the apps running on a simulator,
    /// paired with the actual running bundle id (used to reload that exact app).
    static func match(running bundleIDs: [String], in projects: [DevProject]) -> (project: DevProject, bundleID: String)? {
        for running in bundleIDs {
            if let hit = projects.first(where: { ($0.bundleID).map { bundleMatches(running, $0) } ?? false }) {
                return (hit, running)
            }
        }
        return nil
    }

    static let variantSuffixes: Set<String> = [
        "dev", "development", "staging", "stg", "preview", "debug",
        "beta", "alpha", "prod", "production", "release", "internal"
    ]

    /// Drops a trailing build-variant component (`com.acme.app.dev` -> `com.acme.app`).
    static func bundleBase(_ id: String) -> String {
        guard let dot = id.lastIndex(of: ".") else { return id }
        let last = String(id[id.index(after: dot)...]).lowercased()
        return variantSuffixes.contains(last) ? String(id[..<dot]) : id
    }

    /// Treats `com.acme.app`, `com.acme.app.dev`, `com.acme.app.staging`, … as the same app.
    static func bundleMatches(_ running: String, _ project: String) -> Bool {
        if running == project { return true }
        if running.hasPrefix(project + ".") || project.hasPrefix(running + ".") { return true }
        return bundleBase(running) == bundleBase(project)
    }

    /// Best-guess web framework label from a project's merged dependencies.
    static func detectFramework(_ deps: [String: Any]) -> String? {
        if deps["next"] != nil { return "Next.js" }
        if deps["vite"] != nil { return "Vite" }
        if deps["@remix-run/dev"] != nil { return "Remix" }
        if deps["astro"] != nil { return "Astro" }
        if deps["nuxt"] != nil { return "Nuxt" }
        if deps["@angular/core"] != nil { return "Angular" }
        if deps["@sveltejs/kit"] != nil || deps["svelte"] != nil { return "Svelte" }
        if deps["gatsby"] != nil { return "Gatsby" }
        if deps["react-scripts"] != nil { return "CRA" }
        if deps["react"] != nil { return "React" }
        if deps["vue"] != nil { return "Vue" }
        if deps["express"] != nil || deps["fastify"] != nil || deps["koa"] != nil { return "Node" }
        return nil
    }

    private static func firstXcode(in dir: String, fm: FileManager) -> String? {
        guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { return nil }
        if let ws = entries.first(where: { $0.hasSuffix(".xcworkspace") }) {
            return (dir as NSString).appendingPathComponent(ws)
        }
        if let proj = entries.first(where: { $0.hasSuffix(".xcodeproj") }) {
            return (dir as NSString).appendingPathComponent(proj)
        }
        return nil
    }

    // MARK: - Actions

    /// Best Xcode artifact to open: ios/<App>.xcworkspace, else top-level.
    static func xcodeArtifact(for project: DevProject) -> String? {
        let fm = FileManager.default
        let iosDir = (project.path as NSString).appendingPathComponent("ios")
        return firstXcode(in: iosDir, fm: fm) ?? firstXcode(in: project.path, fm: fm)
    }

    /// Command to build+run the project on a simulator (empty for native — open Xcode instead).
    static func runCommand(for project: DevProject, udid: String?, tv: Bool) -> String {
        let pm = project.packageManager
        switch project.kind {
        case .expo:
            let prefix = tv ? "EXPO_TV=1 " : ""
            let device = udid.map { " --device \"\($0)\"" } ?? ""
            return "\(prefix)\(pm.exec) expo run:ios\(device)"
        case .reactNative:
            let device = udid.map { " --udid \($0)" } ?? ""
            return "\(pm.exec) react-native run-ios\(device)"
        case .nativeApple:
            return ""
        case .web:
            return "\(pm.run) \(project.devScript ?? "dev")"
        }
    }

    /// The Apple platform the project's *current* native `ios/` prebuild targets, read from
    /// `project.pbxproj`. A tvOS prebuild (`react-native-tvos` + `EXPO_TV=1`) builds against
    /// the tvOS SDK (`SDKROOT = appletvos`, `TARGETED_DEVICE_FAMILY = 3`); a phone prebuild
    /// against `iphoneos`. Returns `nil` when there is no prebuild yet (Expo will generate one
    /// on demand) or the platform can't be determined — in which case we never block the run.
    static func prebuiltPlatform(for project: DevProject) -> ApplePlatform? {
        let fm = FileManager.default
        let iosDir = (project.path as NSString).appendingPathComponent("ios")
        guard let entries = try? fm.contentsOfDirectory(atPath: iosDir),
              let proj = entries.first(where: { $0.hasSuffix(".xcodeproj") }) else { return nil }
        let pbx = ((iosDir as NSString).appendingPathComponent(proj) as NSString)
            .appendingPathComponent("project.pbxproj")
        guard let text = try? String(contentsOfFile: pbx, encoding: .utf8) else { return nil }

        if text.contains("SDKROOT = appletvos") { return .tvOS }
        if text.contains("TARGETED_DEVICE_FAMILY = 3")
            || text.contains("TARGETED_DEVICE_FAMILY = \"3\"") { return .tvOS }
        if text.contains("SDKROOT = iphoneos") { return .iOS }
        return nil
    }

    /// Decide how to run a project on `target`, accounting for the platform of the existing
    /// `ios/` prebuild. The native build, not the chosen device, determines what actually
    /// compiles — so when they disagree (e.g. a tvOS prebuild but an iPhone target) we surface
    /// a clear message and a corrective command instead of firing a build that Expo will reject
    /// with "No device UDID or name matching …".
    ///
    /// Only `.expo` projects use Continuous Native Generation, so the prebuild check applies
    /// there; other kinds pass straight through.
    static func runOutcome(for project: DevProject,
                           udid: String?,
                           targetName: String?,
                           target: ApplePlatform) -> RunOutcome {
        // Only Expo uses Continuous Native Generation, so the prebuild guard applies there.
        guard project.kind == .expo else {
            return .command(runCommand(for: project, udid: udid, tv: target.isTV))
        }

        let destination = targetName.map { "“\($0)” (\(target.label))" } ?? target.label

        // The project can't target tvOS at all (no react-native-tvos) — not fixable by a prebuild.
        if target == .tvOS, !project.supportsTV {
            let where_ = targetName.map { "“\($0)”" } ?? "tvOS"
            return .platformMismatch(
                message: "\(project.name) doesn't support tvOS (no react-native-tvos), "
                    + "so it can't run on \(where_).",
                fix: nil)
        }

        // The existing prebuild targets a different platform than the chosen device.
        if let prebuilt = prebuiltPlatform(for: project), prebuilt != target {
            let message = "\(project.name)'s native build in ios/ targets \(prebuilt.label), "
                + "so it can't run on \(destination). Re-prebuild for \(target.label) first."
            let fix = prebuildCommand(for: project, target: target, clean: true)
                + " && " + runCommand(for: project, udid: udid, tv: target.isTV)
            return .platformMismatch(message: message, fix: fix)
        }

        return .command(runCommand(for: project, udid: udid, tv: target.isTV))
    }

    /// Command to restart the Metro bundler with a cleared cache (Expo/RN only).
    /// Frees Metro's port first so an already-running bundler doesn't block the fresh start.
    static func clearCacheCommand(for project: DevProject) -> String? {
        let pm = project.packageManager
        let start: String
        switch project.kind {
        case .expo: start = "\(pm.exec) expo start -c"
        case .reactNative: start = "\(pm.exec) react-native start --reset-cache"
        case .nativeApple, .web: return nil
        }
        return "lsof -ti tcp:8081 | xargs kill -9 2>/dev/null; \(start)"
    }

    static func prebuildCommand(for project: DevProject, clean: Bool) -> String {
        "\(project.packageManager.exec) expo prebuild" + (clean ? " --clean" : "")
    }

    /// Prebuild for a specific Apple platform. Switching platforms requires `--clean` so the
    /// stale `ios/` (e.g. a tvOS project) is regenerated for the new SDK; `EXPO_TV=1` selects
    /// the tvOS variant. The Expo platform is always `ios` — tvOS rides on it via `EXPO_TV`.
    static func prebuildCommand(for project: DevProject, target: ApplePlatform, clean: Bool) -> String {
        let prefix = target.isTV ? "EXPO_TV=1 " : ""
        return "\(prefix)\(project.packageManager.exec) expo prebuild --platform ios" + (clean ? " --clean" : "")
    }

    /// `pod-install` is a standalone helper, so we fetch it via `npx` regardless of the
    /// project's package manager — it needn't be a dependency of the project.
    static func podInstallCommand() -> String {
        "npx pod-install"
    }

    /// Run a package.json script with the project's package manager — e.g. `pnpm build`.
    static func scriptCommand(for project: DevProject, script: String) -> String {
        "\(project.packageManager.run) \(script)"
    }

    /// Remove the usual web/JS build + cache directories. Runs in Terminal so it's visible;
    /// ignores anything that isn't there.
    static func cleanCachesCommand() -> String {
        let dirs = [".next", ".nuxt", ".astro", ".svelte-kit", ".vite", ".turbo",
                    ".parcel-cache", ".eslintcache", "dist", "build", "node_modules/.cache"]
        return "rm -rf " + dirs.joined(separator: " ") + " 2>/dev/null; echo '✓ cleaned build caches'"
    }

    /// package.json scripts in a sensible order — common ones first, then alphabetical.
    static func prioritizedScripts(_ names: [String]) -> [String] {
        let priority = ["dev", "start", "build", "preview", "serve", "test",
                        "lint", "typecheck", "type-check", "format", "storybook"]
        let rank = Dictionary(uniqueKeysWithValues: priority.enumerated().map { ($1, $0) })
        return names.sorted { lhs, rhs in
            let lr = rank[lhs] ?? Int.max, rr = rank[rhs] ?? Int.max
            if lr != rr { return lr < rr }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }

    /// Split running dev servers into those that belong to a scanned project (keyed by path)
    /// and "orphans" started elsewhere — so the Projects panel can show both without pinging.
    static func matchServers(_ servers: [ActiveBundler], to projects: [DevProject])
        -> (matched: [String: ActiveBundler], orphans: [ActiveBundler]) {
        var matched: [String: ActiveBundler] = [:]
        var matchedPIDs = Set<Int>()
        for project in projects {
            if let server = servers.first(where: { belongs($0, to: project) }) {
                matched[project.path] = server
                matchedPIDs.insert(server.pid)
            }
        }
        let orphans = servers.filter { !matchedPIDs.contains($0.pid) }
        return (matched, orphans)
    }

    /// True when a server's working directory is the project root or a subdirectory of it.
    private static func belongs(_ server: ActiveBundler, to project: DevProject) -> Bool {
        server.cwd == project.path || server.cwd.hasPrefix(project.path + "/")
    }
}
