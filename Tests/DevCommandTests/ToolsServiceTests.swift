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

    func testURLEncodeMatchesEncodeURIComponent() {
        XCTAssertEqual(ToolsService.urlEncode("a b&c=d/e?f"), "a%20b%26c%3Dd%2Fe%3Ff")
        XCTAssertEqual(ToolsService.urlEncode("safe-chars_are.kept~"), "safe-chars_are.kept~")
        XCTAssertEqual(ToolsService.urlEncode("héllo"), "h%C3%A9llo")
    }

    func testURLDecodeRoundTripsAndRejectsBadEscapes() {
        let original = "name=Ada Lovelace & co/50%"
        XCTAssertEqual(ToolsService.urlDecode(ToolsService.urlEncode(original)), original)
        XCTAssertEqual(ToolsService.urlDecode("a%20b"), "a b")
        XCTAssertNil(ToolsService.urlDecode("100%zz"))
    }

    func testSHA256KnownVectors() {
        XCTAssertEqual(ToolsService.sha256("abc"),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(ToolsService.sha256(""),
                       "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    func testPrettyJSONIndentsSortsAndValidates() {
        XCTAssertEqual(ToolsService.prettyJSON(#"{"b":1,"a":[true,null],"url":"https://x.dev/a"}"#), """
        {
          "a" : [
            true,
            null
          ],
          "b" : 1,
          "url" : "https://x.dev/a"
        }
        """)
        XCTAssertNil(ToolsService.prettyJSON("{not json}"))
        XCTAssertNil(ToolsService.prettyJSON(""))
    }

    func testDescribeEpochPicksTheUnitFromMagnitude() {
        let utc = TimeZone(identifier: "UTC")!, posix = Locale(identifier: "en_US_POSIX")
        // The same instant written in seconds, milliseconds, microseconds and nanoseconds.
        for text in ["1700000000", "1700000000000", "1700000000000000", "1700000000000000000"] {
            let described = ToolsService.describeEpoch(text, timeZone: utc, locale: posix)
            XCTAssertEqual(described?.utc, "2023-11-14T22:13:20Z", "for \(text)")
        }
        XCTAssertEqual(ToolsService.describeEpoch(" 0 ", timeZone: utc, locale: posix)?.utc, "1970-01-01T00:00:00Z")
        XCTAssertEqual(ToolsService.describeEpoch("-86400", timeZone: utc, locale: posix)?.utc, "1969-12-31T00:00:00Z")
    }

    func testDescribeEpochLocalLineUsesTheGivenTimeZone() {
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!, posix = Locale(identifier: "en_US_POSIX")
        let local = ToolsService.describeEpoch("1700000000", timeZone: tokyo, locale: posix)?.local ?? ""
        XCTAssertTrue(local.contains("Nov 15, 2023"), local)   // 22:13 UTC is already the 15th in Tokyo
        XCTAssertTrue(local.contains("7:13:20"), local)
    }

    func testDescribeEpochRejectsNonNumbers() {
        for text in ["", "   ", "tomorrow", "1e9", "inf", "nan", "0x10", "12:30"] {
            XCTAssertNil(ToolsService.describeEpoch(text), "accepted \(text)")
        }
    }
}
