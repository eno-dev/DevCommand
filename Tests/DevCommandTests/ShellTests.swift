import XCTest
@testable import DevCommand

final class ShellTests: XCTestCase {
    func testBasicOutputAndExitCode() async {
        let result = await Shell.run("/bin/echo", ["hello"])
        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "hello")
    }

    func testNonzeroExitSurfacesError() async {
        let result = await Shell.run("/bin/ls", ["/no/such/path/devcommand-xyz"])
        XCTAssertFalse(result.ok)
        XCTAssertFalse(result.briefError.isEmpty)
    }

    func testLaunchFailureDoesNotHang() async {
        let result = await Shell.run("/definitely/not/a/binary")
        XCTAssertEqual(result.exitCode, -1)
    }

    /// The core fix: a long-running command must be terminated at the timeout, not hang and
    /// hold threads forever (which previously spun the app to 100% CPU over time).
    func testTimeoutTerminatesHungProcess() async {
        let start = Date()
        let result = await Shell.run("/bin/sleep", ["30"], timeout: 1)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertFalse(result.ok)            // killed, not a clean exit 0
        XCTAssertLessThan(elapsed, 10)       // returned promptly instead of hanging 30s
    }

    /// Many concurrent runs must all complete (event-driven reads, no thread explosion).
    func testManyConcurrentRunsAllComplete() async {
        let oks = await withTaskGroup(of: Bool.self) { group -> Int in
            for index in 0..<40 {
                group.addTask { await Shell.run("/bin/echo", ["\(index)"]).ok }
            }
            var count = 0
            for await ok in group where ok { count += 1 }
            return count
        }
        XCTAssertEqual(oks, 40)
    }
}
