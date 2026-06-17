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
}
