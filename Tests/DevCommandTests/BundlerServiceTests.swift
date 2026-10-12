import XCTest
@testable import DevCommand

final class BundlerServiceTests: XCTestCase {
    func testParseCwdsTagsEachCwdToItsPID() {
        // `lsof -Fpn` output for several PIDs in one call.
        let output = """
        p123
        n/Users/me/dev/app
        p456
        n/Users/me/dev/web
        """
        let map = BundlerService.parseCwds(output)
        XCTAssertEqual(map.count, 2)
        XCTAssertEqual(map[123], "/Users/me/dev/app")
        XCTAssertEqual(map[456], "/Users/me/dev/web")
    }

    func testParseCwdsIgnoresUnpairedAndEmpty() {
        XCTAssertTrue(BundlerService.parseCwds("").isEmpty)
        // A leading cwd with no pid is ignored; first cwd per pid wins.
        XCTAssertTrue(BundlerService.parseCwds("n/orphan").isEmpty)
    }

    func testIsAliveSeesThisProcessButNotAFreePID() {
        XCTAssertTrue(BundlerService.isAlive(Int(getpid())))
        XCTAssertTrue(BundlerService.isAlive(1))          // launchd: exists, not ours (EPERM)
        XCTAssertFalse(BundlerService.isAlive(Int(Int32.max) - 1))   // far beyond any real pid
    }

    /// A restart waits for the old server to go away: gone already returns at once, still
    /// running gives up at the timeout instead of hanging.
    func testWaitForExit() async {
        let gone = await BundlerService.waitForExit(pid: Int(Int32.max) - 1, timeout: 1)
        XCTAssertTrue(gone)
        let start = Date()
        let stillThere = await BundlerService.waitForExit(pid: Int(getpid()), timeout: 0.4)
        XCTAssertFalse(stillThere)
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }
}
