import XCTest
@testable import DevCommand

final class ModelTests: XCTestCase {

    // MARK: ShellResult

    func testShellResultOkAndOutput() {
        XCTAssertTrue(ShellResult(stdout: "x", stderr: "", exitCode: 0).ok)
        XCTAssertFalse(ShellResult(stdout: "", stderr: "boom", exitCode: 1).ok)
        XCTAssertEqual(ShellResult(stdout: "out", stderr: "err", exitCode: 0).output, "out")
        XCTAssertEqual(ShellResult(stdout: "", stderr: "err", exitCode: 0).output, "err")  // falls back
    }

    func testShellResultBriefError() {
        XCTAssertEqual(ShellResult(stdout: "", stderr: "Permission denied\nextra", exitCode: 1).briefError,
                       "Permission denied")
        XCTAssertEqual(ShellResult(stdout: "only-stdout", stderr: "", exitCode: 2).briefError, "only-stdout")
        XCTAssertEqual(ShellResult(stdout: "", stderr: "", exitCode: 5).briefError, "exited with code 5")
    }

    // MARK: Simulator

    func testSimulatorFlags() {
        let booted = Simulator(udid: "a", name: "iPhone", state: "Booted",
                               runtimeKey: "com.apple.CoreSimulator.SimRuntime.iOS-26-5")
        XCTAssertTrue(booted.isBooted)
        XCTAssertFalse(booted.isTV)

        let tv = Simulator(udid: "b", name: "Apple TV", state: "Shutdown",
                           runtimeKey: "com.apple.CoreSimulator.SimRuntime.tvOS-18-0")
        XCTAssertFalse(tv.isBooted)
        XCTAssertTrue(tv.isTV)
    }

    // MARK: ActiveBundler

    func testActiveBundlerLabelAndScheme() {
        let metro = ActiveBundler(pid: 10, port: 8081, cwd: "/x", projectName: "x")
        XCTAssertEqual(metro.label, "Metro")
        XCTAssertTrue(metro.supportsExpoScheme)
        XCTAssertEqual(metro.id, 10)

        let web = ActiveBundler(pid: 11, port: 3000, cwd: "/y", projectName: "y")
        XCTAssertEqual(web.label, "Node / Next")
        XCTAssertFalse(web.supportsExpoScheme)

        XCTAssertEqual(ActiveBundler(pid: 12, port: 65000, cwd: "/z", projectName: "z").label, "Bundler")
    }

    // MARK: DevProject / ProjectKind

    func testProjectKindLabelPrefersFramework() {
        let web = DevProject(name: "W", path: "/w", kind: .web, hasIOS: false, hasPods: false,
                             supportsTV: false, framework: "Vite", devScript: "dev", bundleID: nil,
                             packageManager: .pnpm, scripts: [])
        XCTAssertEqual(web.kindLabel, "Vite")
        XCTAssertTrue(web.isJavaScript)
        XCTAssertFalse(web.usesMetro)

        let rn = DevProject(name: "R", path: "/r", kind: .reactNative, hasIOS: true, hasPods: true,
                            supportsTV: true, framework: nil, devScript: nil, bundleID: "com.r",
                            packageManager: .yarn, scripts: ["start"])
        XCTAssertEqual(rn.kindLabel, "React Native")
        XCTAssertTrue(rn.usesMetro)
    }

    func testProjectKindIcons() {
        XCTAssertEqual(ProjectKind.expo.icon, "apps.iphone")
        XCTAssertEqual(ProjectKind.reactNative.icon, "atom")
        XCTAssertEqual(ProjectKind.nativeApple.icon, "applelogo")
        XCTAssertEqual(ProjectKind.web.icon, "globe")
    }

    // MARK: String.singleQuoted

    func testSingleQuoted() {
        XCTAssertEqual("abc".singleQuoted, "'abc'")
        XCTAssertEqual("/path with spaces".singleQuoted, "'/path with spaces'")
        XCTAssertEqual("a'b".singleQuoted, "'a'\\''b'")   // apostrophe escaped for the shell
    }

    // MARK: ListeningPort extras

    func testListeningPortFlags() {
        func port(_ p: Int, _ cmd: String = "node", _ addr: String = "*") -> ListeningPort {
            ListeningPort(port: p, pid: 1, command: cmd, user: "me", address: addr)
        }
        XCTAssertTrue(port(5432, "postgres", "127.0.0.1").isLoopback)
        XCTAssertTrue(port(5432, "postgres", "::1").isLoopback)
        XCTAssertFalse(port(8081, "node", "*").isLoopback)
        XCTAssertTrue(port(6006).isStorybook)
        XCTAssertTrue(port(6007).isStorybook)
        XCTAssertFalse(port(8081).isStorybook)
        XCTAssertTrue(port(8081, "node").isDev)            // dev label
        XCTAssertTrue(port(45000, "postgres").isDev)       // dev command, non-dev port
        XCTAssertFalse(port(45000, "Mail").isDev)
    }
}
