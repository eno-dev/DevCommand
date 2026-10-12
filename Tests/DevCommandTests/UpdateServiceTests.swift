import XCTest
@testable import DevCommand

final class UpdateServiceTests: XCTestCase {
    func testLatestVersionFromReleaseJSON() {
        let json = Data(#"{"tag_name":"v0.3.1","name":"DevCommand 0.3.1","draft":false}"#.utf8)
        XCTAssertEqual(UpdateService.latestVersion(fromReleaseJSON: json), "0.3.1")
        XCTAssertEqual(UpdateService.latestVersion(fromReleaseJSON: Data(#"{"tag_name":"1.2"}"#.utf8)), "1.2")
    }

    /// The version is shown in Settings, so anything that isn't a plain dotted number is refused.
    func testLatestVersionRejectsAnythingButADottedNumber() {
        for tag in ["", "v", "latest", "v1.2-beta", "1..2", "v1.2.3 <b>", "1.2.3.4.5", "v1234567.0"] {
            let json = try! JSONSerialization.data(withJSONObject: ["tag_name": tag])
            XCTAssertNil(UpdateService.latestVersion(fromReleaseJSON: json), "accepted \(tag)")
        }
        XCTAssertNil(UpdateService.latestVersion(fromReleaseJSON: Data("not json".utf8)))
        XCTAssertNil(UpdateService.latestVersion(fromReleaseJSON: Data(#"{"message":"rate limited"}"#.utf8)))
    }

    func testIsNewerComparesNumerically() {
        XCTAssertTrue(UpdateService.isNewer("0.3.0", than: "0.2.0"))
        XCTAssertTrue(UpdateService.isNewer("0.10.0", than: "0.9.3"))   // not a string compare
        XCTAssertTrue(UpdateService.isNewer("1.0", than: "0.99.99"))
        XCTAssertTrue(UpdateService.isNewer("0.2.1", than: "0.2"))
        XCTAssertFalse(UpdateService.isNewer("0.2.0", than: "0.2.0"))
        XCTAssertFalse(UpdateService.isNewer("0.2", than: "0.2.0"))     // same version, fewer parts
        XCTAssertFalse(UpdateService.isNewer("0.1.9", than: "0.2.0"))   // a source build ahead of the release
    }
}
