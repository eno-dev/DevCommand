import XCTest
@testable import DevCommand

final class ProjectServiceTests: XCTestCase {

    // MARK: Bundle-id matching

    func testBundleBaseDropsVariantSuffix() {
        XCTAssertEqual(ProjectService.bundleBase("com.acme.app.dev"), "com.acme.app")
        XCTAssertEqual(ProjectService.bundleBase("com.acme.app.staging"), "com.acme.app")
        XCTAssertEqual(ProjectService.bundleBase("com.acme.app"), "com.acme.app")
        XCTAssertEqual(ProjectService.bundleBase("com.acme.widgets"), "com.acme.widgets") // not a variant
    }

    func testBundleMatchesAcrossVariants() {
        XCTAssertTrue(ProjectService.bundleMatches("com.acme.app.dev", "com.acme.app"))
        XCTAssertTrue(ProjectService.bundleMatches("com.acme.app", "com.acme.app.staging"))
        XCTAssertTrue(ProjectService.bundleMatches("com.acme.app", "com.acme.app"))
        XCTAssertFalse(ProjectService.bundleMatches("com.other.app", "com.acme.app"))
    }

    // MARK: Framework detection

    func testDetectFrameworkPrecedence() {
        XCTAssertEqual(ProjectService.detectFramework(["next": 1, "react": 1]), "Next.js")
        XCTAssertEqual(ProjectService.detectFramework(["vite": 1]), "Vite")
        XCTAssertEqual(ProjectService.detectFramework(["react": 1]), "React")
        XCTAssertEqual(ProjectService.detectFramework(["express": 1]), "Node")
        XCTAssertNil(ProjectService.detectFramework([:]))
    }

    // MARK: Package-manager detection from lockfiles

    func testPackageManagerDetection() throws {
        let fm = FileManager.default
        XCTAssertEqual(try detect(lockfiles: ["bun.lockb"], fm), .bun)
        XCTAssertEqual(try detect(lockfiles: ["pnpm-lock.yaml"], fm), .pnpm)
        XCTAssertEqual(try detect(lockfiles: ["yarn.lock"], fm), .yarn)
        XCTAssertEqual(try detect(lockfiles: ["package-lock.json"], fm), .npm)
        XCTAssertEqual(try detect(lockfiles: [], fm), .npm)
        // bun wins when several are present
        XCTAssertEqual(try detect(lockfiles: ["yarn.lock", "bun.lockb"], fm), .bun)
    }

    private func detect(lockfiles: [String], _ fm: FileManager) throws -> PackageManager {
        let dir = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("devcommand-pm-\(UUID().uuidString)")
        try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: dir) }
        for file in lockfiles {
            fm.createFile(atPath: (dir as NSString).appendingPathComponent(file), contents: Data())
        }
        return PackageManager.detect(at: dir, fm: fm)
    }

    // MARK: Run commands honour the package manager

    func testRunCommandUsesPackageManager() {
        let pnpmWeb = project(kind: .web, pm: .pnpm, devScript: "dev")
        XCTAssertEqual(ProjectService.runCommand(for: pnpmWeb, udid: nil, tv: false), "pnpm dev")

        let yarnExpo = project(kind: .expo, pm: .yarn)
        XCTAssertEqual(ProjectService.runCommand(for: yarnExpo, udid: "X", tv: false),
                       "yarn expo run:ios --device \"X\"")

        let npmExpoTV = project(kind: .expo, pm: .npm)
        XCTAssertEqual(ProjectService.runCommand(for: npmExpoTV, udid: nil, tv: true),
                       "EXPO_TV=1 npx expo run:ios")

        let bunRN = project(kind: .reactNative, pm: .bun)
        XCTAssertEqual(ProjectService.runCommand(for: bunRN, udid: "U", tv: false),
                       "bunx react-native run-ios --udid U")
    }

    func testClearCacheAndPrebuildUsePackageManager() {
        let yarnExpo = project(kind: .expo, pm: .yarn)
        XCTAssertEqual(ProjectService.clearCacheCommand(for: yarnExpo),
                       "lsof -ti tcp:8081 | xargs kill -9 2>/dev/null; yarn expo start -c")
        XCTAssertEqual(ProjectService.prebuildCommand(for: yarnExpo, clean: true), "yarn expo prebuild --clean")
        XCTAssertNil(ProjectService.clearCacheCommand(for: project(kind: .web, pm: .npm)))
    }

    // MARK: Scripts, cache cleaning, running-server matching

    func testPrioritizedScriptsOrdering() {
        let ordered = ProjectService.prioritizedScripts(["zebra", "build", "dev", "lint", "alpha"])
        XCTAssertEqual(ordered, ["dev", "build", "lint", "alpha", "zebra"])
    }

    func testScriptCommandUsesPackageManager() {
        XCTAssertEqual(ProjectService.scriptCommand(for: project(kind: .web, pm: .pnpm), script: "build"), "pnpm build")
        XCTAssertEqual(ProjectService.scriptCommand(for: project(kind: .web, pm: .npm), script: "test"), "npm run test")
        XCTAssertEqual(ProjectService.scriptCommand(for: project(kind: .web, pm: .bun), script: "lint"), "bun run lint")
    }

    func testCleanCachesCommandTargetsBuildDirs() {
        let cmd = ProjectService.cleanCachesCommand()
        XCTAssertTrue(cmd.hasPrefix("rm -rf "))
        for dir in [".next", ".vite", ".turbo", "dist", "node_modules/.cache"] {
            XCTAssertTrue(cmd.contains(dir), "expected \(dir) in clean command")
        }
    }

    func testMatchServersSplitsMatchedAndOrphans() {
        let site = project(kind: .web, pm: .npm, path: "/Users/me/dev/site")
        let app = project(kind: .expo, pm: .npm, path: "/Users/me/dev/app")
        let servers = [
            ActiveBundler(pid: 1, port: 5173, cwd: "/Users/me/dev/site", projectName: "site"),
            ActiveBundler(pid: 2, port: 8081, cwd: "/Users/me/dev/app/ios", projectName: "ios"), // subdir of a project
            ActiveBundler(pid: 3, port: 3000, cwd: "/Users/me/elsewhere", projectName: "elsewhere"),
        ]
        let (matched, orphans) = ProjectService.matchServers(servers, to: [site, app])
        XCTAssertEqual(matched["/Users/me/dev/site"]?.port, 5173)
        XCTAssertEqual(matched["/Users/me/dev/app"]?.port, 8081)   // matched via subdirectory
        XCTAssertEqual(orphans.map(\.pid), [3])                    // the one outside any project
    }

    private func project(kind: ProjectKind, pm: PackageManager, devScript: String? = nil,
                         path: String = "/tmp/App", scripts: [String] = []) -> DevProject {
        DevProject(name: "App", path: path, kind: kind,
                   hasIOS: kind != .web, hasPods: false, supportsTV: false,
                   framework: nil, devScript: devScript, bundleID: nil,
                   packageManager: pm, scripts: scripts)
    }

    // MARK: Prebuilt-platform detection & run-outcome guard

    /// Make a throwaway project dir whose `ios/App.xcodeproj/project.pbxproj` carries the
    /// given build settings (or no `ios/` at all when `pbxproj` is nil). Returns the path.
    private func makeProjectDir(pbxproj: String?) throws -> String {
        let fm = FileManager.default
        let dir = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("devcommand-proj-\(UUID().uuidString)")
        try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? fm.removeItem(atPath: dir) }
        if let pbxproj {
            let xcodeproj = (dir as NSString).appendingPathComponent("ios/App.xcodeproj")
            try fm.createDirectory(atPath: xcodeproj, withIntermediateDirectories: true)
            try pbxproj.write(toFile: (xcodeproj as NSString).appendingPathComponent("project.pbxproj"),
                              atomically: true, encoding: .utf8)
        }
        return dir
    }

    private let tvPbx  = "buildSettings = {\n  SDKROOT = appletvos;\n  TARGETED_DEVICE_FAMILY = 3;\n};"
    private let iosPbx = "buildSettings = {\n  SDKROOT = iphoneos;\n  TARGETED_DEVICE_FAMILY = \"1,2\";\n};"

    func testPrebuiltPlatformDetection() throws {
        let tv  = project(kind: .expo, pm: .npm, path: try makeProjectDir(pbxproj: tvPbx))
        let ios = project(kind: .expo, pm: .npm, path: try makeProjectDir(pbxproj: iosPbx))
        let bare = project(kind: .expo, pm: .npm, path: try makeProjectDir(pbxproj: nil))
        XCTAssertEqual(ProjectService.prebuiltPlatform(for: tv), .tvOS)
        XCTAssertEqual(ProjectService.prebuiltPlatform(for: ios), .iOS)
        XCTAssertNil(ProjectService.prebuiltPlatform(for: bare))   // no prebuild yet → don't block
    }

    func testRunOutcomeFlagsTVPrebuildVsPhone() throws {
        let tv = project(kind: .expo, pm: .npm, path: try makeProjectDir(pbxproj: tvPbx))
        let outcome = ProjectService.runOutcome(for: tv, udid: "00008150-XYZ",
                                                targetName: "Eno's iPhone", target: .iOS)
        guard case let .platformMismatch(message, fixOpt) = outcome else {
            return XCTFail("expected a platform mismatch, got \(outcome)")
        }
        let fix = try XCTUnwrap(fixOpt)
        XCTAssertTrue(message.contains("tvOS"))            // names the prebuild's platform
        XCTAssertTrue(message.contains("Eno's iPhone"))    // names the target
        XCTAssertTrue(fix.contains("expo prebuild --platform ios --clean"))
        XCTAssertFalse(fix.contains("EXPO_TV=1"))          // target is iOS, not TV
        XCTAssertTrue(fix.contains("expo run:ios --device \"00008150-XYZ\""))
    }

    func testRunOutcomeFlagsPhonePrebuildVsTV() throws {
        // A TV-capable project prebuilt for iOS, asked to run on an Apple TV.
        let ios = DevProject(name: "App", path: try makeProjectDir(pbxproj: iosPbx), kind: .expo,
                             hasIOS: true, hasPods: false, supportsTV: true, framework: nil,
                             devScript: nil, bundleID: nil, packageManager: .npm, scripts: [])
        let outcome = ProjectService.runOutcome(for: ios, udid: nil, targetName: "Apple TV", target: .tvOS)
        guard case let .platformMismatch(_, fixOpt) = outcome else {
            return XCTFail("expected a platform mismatch, got \(outcome)")
        }
        let fix = try XCTUnwrap(fixOpt)
        XCTAssertTrue(fix.hasPrefix("EXPO_TV=1 "))          // target is tvOS
        XCTAssertTrue(fix.contains("expo prebuild --platform ios --clean"))
    }

    func testRunOutcomeRejectsTVTargetForNonTVProject() throws {
        // No react-native-tvos → can't run on tvOS, and no prebuild can fix it (fix == nil).
        let ios = project(kind: .expo, pm: .npm, path: try makeProjectDir(pbxproj: iosPbx))  // supportsTV: false
        let outcome = ProjectService.runOutcome(for: ios, udid: "TVID", targetName: "Living Room", target: .tvOS)
        guard case let .platformMismatch(message, fix) = outcome else {
            return XCTFail("expected a platform mismatch, got \(outcome)")
        }
        XCTAssertNil(fix)                                  // nothing to copy — advisory only
        XCTAssertTrue(message.contains("doesn't support tvOS"))
        XCTAssertTrue(message.contains("Living Room"))
    }

    func testRunOutcomeAllowsMatchingPlatform() throws {
        // A TV-capable project, prebuilt for tvOS, run on an Apple TV — no mismatch.
        let tv = DevProject(name: "App", path: try makeProjectDir(pbxproj: tvPbx), kind: .expo,
                            hasIOS: true, hasPods: false, supportsTV: true, framework: nil,
                            devScript: nil, bundleID: nil, packageManager: .npm, scripts: [])
        let outcome = ProjectService.runOutcome(for: tv, udid: "TVID", targetName: "Apple TV", target: .tvOS)
        guard case let .command(cmd) = outcome else { return XCTFail("expected a command, got \(outcome)") }
        XCTAssertEqual(cmd, "EXPO_TV=1 npx expo run:ios --device \"TVID\"")
    }

    func testRunOutcomeNoPrebuildJustRuns() throws {
        let bare = project(kind: .expo, pm: .npm, path: try makeProjectDir(pbxproj: nil))
        let outcome = ProjectService.runOutcome(for: bare, udid: "X", targetName: "Phone", target: .iOS)
        guard case let .command(cmd) = outcome else { return XCTFail("expected a command, got \(outcome)") }
        XCTAssertEqual(cmd, "npx expo run:ios --device \"X\"")
    }

    func testRunOutcomeNonExpoPassesThrough() throws {
        // A bare React Native project with a tvOS prebuild isn't CNG — no prebuild guard applies.
        let rn = project(kind: .reactNative, pm: .npm, path: try makeProjectDir(pbxproj: tvPbx))
        let outcome = ProjectService.runOutcome(for: rn, udid: "U", targetName: "Phone", target: .iOS)
        guard case let .command(cmd) = outcome else { return XCTFail("expected a command, got \(outcome)") }
        XCTAssertEqual(cmd, "npx react-native run-ios --udid U")
    }
}
