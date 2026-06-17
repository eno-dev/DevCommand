import XCTest
@testable import DevCommand

final class ToolsServiceTests: XCTestCase {
    func testBase64RoundTrip() {
        XCTAssertEqual(ToolsService.base64Encode("hello"), "aGVsbG8=")
        XCTAssertEqual(ToolsService.base64Decode("aGVsbG8="), "hello")
    }

    func testBase64DecodeAcceptsUnpaddedAndURLSafe() {
        XCTAssertEqual(ToolsService.base64Decode("aGVsbG8"), "hello")          // missing padding
        // base64url of {"a":">"} uses '-'/'_'; ensure URL-safe alphabet decodes.
        let urlSafe = Data("{\"a\":\"?\"}".utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        XCTAssertEqual(ToolsService.base64Decode(urlSafe), "{\"a\":\"?\"}")
    }

    func testBase64DecodeRejectsGarbage() {
        XCTAssertNil(ToolsService.base64Decode("@@@not base64@@@"))
    }

    func testJWTDecode() {
        let token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9" +
            ".eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ" +
            ".SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
        let decoded = ToolsService.decodeJWT(token)
        XCTAssertNotNil(decoded)
        XCTAssertTrue(decoded?.contains("\"alg\"") ?? false)
        XCTAssertTrue(decoded?.contains("John Doe") ?? false)
        XCTAssertTrue(decoded?.contains("1234567890") ?? false)
    }

    func testJWTDecodeRejectsNonJWT() {
        XCTAssertNil(ToolsService.decodeJWT("just-a-string"))
    }

    func testSecretTokenIsRequestedLength() {
        // 32 bytes -> 44 base64 chars (with padding); also ensure two calls differ.
        let a = ToolsService.secretToken()
        let b = ToolsService.secretToken()
        XCTAssertEqual(a.count, 44)
        XCTAssertNotEqual(a, b)
    }

    func testEpochNowSecondsAndMillisAgree() {
        let (seconds, millis) = ToolsService.epochNow()
        guard let sec = Int(seconds), let ms = Int(millis) else {
            return XCTFail("epoch values should be integers")
        }
        XCTAssertEqual(ms / 1000, sec)          // same instant, ms == seconds * 1000 (truncated)
        XCTAssertGreaterThan(sec, 1_700_000_000) // sometime after 2023
    }

    func testUUIDFormat() {
        let uuid = ToolsService.uuid()
        XCTAssertEqual(uuid.count, 36)
        XCTAssertEqual(uuid.filter { $0 == "-" }.count, 4)
        XCTAssertNotNil(UUID(uuidString: uuid))
    }
}
