import XCTest
@testable import DevCommand

final class DoctorServiceTests: XCTestCase {
    func testParseProbeSplitsOnFirstColon() {
        let output = """
        node:v20.11.1
        npm:10.2.4
        git:git version 2.39.5
        pod:
        watchman:/opt/homebrew/bin/watchman
        xcode:/Applications/Xcode.app/Contents/Developer
        """
        let fields = DoctorService.parseProbe(output)
        XCTAssertEqual(fields["node"], "v20.11.1")
        XCTAssertEqual(fields["npm"], "10.2.4")
        XCTAssertEqual(fields["git"], "git version 2.39.5")   // value keeps text after the first colon
        XCTAssertEqual(fields["pod"], "")                      // empty value preserved
        XCTAssertEqual(fields["watchman"], "/opt/homebrew/bin/watchman")
        XCTAssertEqual(fields["xcode"], "/Applications/Xcode.app/Contents/Developer")
    }

    func testParseProbeIgnoresMalformedLines() {
        let fields = DoctorService.parseProbe("garbage-no-colon\nnode:v1")
        XCTAssertEqual(fields.count, 1)
        XCTAssertEqual(fields["node"], "v1")
    }

    func testVersionCheckPresent() {
        let check = DoctorService.versionCheck(["node": "v20.11.1"], key: "node", id: "node",
                                               title: "Node.js", missing: .fail, install: "brew install node")
        XCTAssertEqual(check.status, .ok)
        XCTAssertEqual(check.detail, "v20.11.1")
        XCTAssertNil(check.fixCommand)
    }

    func testVersionCheckMissing() {
        let check = DoctorService.versionCheck([:], key: "node", id: "node",
                                               title: "Node.js", missing: .fail, install: "brew install node")
        XCTAssertEqual(check.status, .fail)
        XCTAssertEqual(check.detail, "Not installed")
        XCTAssertEqual(check.fixLabel, "Install")
        XCTAssertEqual(check.fixCommand, "brew install node")
    }

    func testPresenceCheck() {
        let present = DoctorService.presenceCheck(["watchman": "/bin/watchman"], key: "watchman",
                                                  id: "watchman", title: "Watchman", missing: .warn, install: "x")
        XCTAssertEqual(present.status, .ok)
        XCTAssertEqual(present.detail, "Installed")

        let absent = DoctorService.presenceCheck(["watchman": ""], key: "watchman",
                                                 id: "watchman", title: "Watchman", missing: .warn, install: "x")
        XCTAssertEqual(absent.status, .warn)
        XCTAssertEqual(absent.detail, "Not installed")
    }

    func testXcodeCheck() {
        let ok = DoctorService.xcodeCheck(["xcode": "/Applications/Xcode.app/Contents/Developer"])
        XCTAssertEqual(ok.status, .ok)
        let missing = DoctorService.xcodeCheck([:])
        XCTAssertEqual(missing.status, .warn)
        XCTAssertEqual(missing.fixCommand, "xcode-select --install")
    }

    func testIsLarge() {
        XCTAssertTrue(DoctorService.isLarge("12G"))
        XCTAssertTrue(DoctorService.isLarge("1.5T"))
        XCTAssertTrue(DoctorService.isLarge("5G"))      // boundary: >= 5
        XCTAssertFalse(DoctorService.isLarge("4.9G"))
        XCTAssertFalse(DoctorService.isLarge("500M"))
        XCTAssertFalse(DoctorService.isLarge("Empty"))
    }
}
