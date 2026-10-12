import Foundation
import CryptoKit

enum ToolsService {

    // MARK: Generators

    static func uuid() -> String { UUID().uuidString }

    static func epochNow() -> (seconds: String, millis: String) {
        let now = Date().timeIntervalSince1970
        return (String(Int(now)), String(Int(now * 1000)))
    }

    /// 32 cryptographically-random bytes, base64-encoded — handy for JWT secrets / API keys.
    static func secretToken(byteCount: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        for index in bytes.indices { bytes[index] = UInt8.random(in: 0...255) }
        return Data(bytes).base64EncodedString()
    }

    /// Read a Unix timestamp and render it as UTC ISO 8601 plus the local date and time. The unit
    /// (seconds, milliseconds, microseconds or nanoseconds) is picked from the magnitude, since
    /// that is how these numbers show up in logs and APIs.
    static func describeEpoch(_ text: String, timeZone: TimeZone = .current,
                              locale: Locale = .current) -> (utc: String, local: String)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Plain decimal only: Double() alone would also accept "inf", "nan", hex and exponents.
        guard !trimmed.isEmpty,
              trimmed.allSatisfy({ ($0.isASCII && $0.isNumber) || $0 == "." || $0 == "-" }),
              let value = Double(trimmed) else { return nil }
        let seconds: Double
        switch abs(value) {
        case ..<1e11: seconds = value
        case ..<1e14: seconds = value / 1e3
        case ..<1e17: seconds = value / 1e6
        default: seconds = value / 1e9
        }
        let date = Date(timeIntervalSince1970: seconds)

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let localFormatter = DateFormatter()
        localFormatter.dateStyle = .medium
        localFormatter.timeStyle = .long
        localFormatter.timeZone = timeZone
        localFormatter.locale = locale
        return (iso.string(from: date), localFormatter.string(from: date))
    }

    // MARK: Converters

    static func base64Encode(_ text: String) -> String {
        Data(text.utf8).base64EncodedString()
    }

    static func base64Decode(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Try standard base64 first, then fall back to base64url / unpadded (JWTs, URL-safe tokens).
        if let data = Data(base64Encoded: trimmed),
           let string = String(data: data, encoding: .utf8) { return string }
        var url = trimmed
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while url.count % 4 != 0 { url += "=" }
        guard let data = Data(base64Encoded: url) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Characters `encodeURIComponent` leaves alone; everything else gets percent-encoded.
    private static let urlUnreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// Percent-encode text so it is safe as a single URL component (a query value, a path segment).
    static func urlEncode(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: urlUnreserved) ?? text
    }

    /// Reverse percent-encoding. nil when the input has a malformed escape.
    static func urlDecode(_ text: String) -> String? {
        text.trimmingCharacters(in: .whitespacesAndNewlines).removingPercentEncoding
    }

    /// SHA-256 of the text's UTF-8 bytes, as lowercase hex.
    static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Re-indent a JSON object or array with sorted keys. nil when the input is not valid JSON.
    static func prettyJSON(_ text: String) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)),
              let pretty = try? JSONSerialization.data(
                withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        else { return nil }
        return String(decoding: pretty, as: UTF8.self)
    }

    /// Decode a JWT's header + payload (base64url) into pretty JSON. Does not verify the signature.
    static func decodeJWT(_ token: String) -> String? {
        let parts = token.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".")
        guard parts.count >= 2,
              let header = decodeSegment(parts[0]),
              let payload = decodeSegment(parts[1]) else { return nil }
        return "// header\n\(header)\n\n// payload\n\(payload)"
    }

    private static func decodeSegment(_ segment: Substring) -> String? {
        var base64 = String(segment)
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64) else { return nil }
        if let object = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: object,
                                                    options: [.prettyPrinted, .sortedKeys]) {
            return String(decoding: pretty, as: UTF8.self)
        }
        return String(data: data, encoding: .utf8)
    }

    // MARK: Maintenance

    static func runMaintenance(_ tool: DevTool) async -> ShellResult {
        switch tool {
        case .derivedData:
            return await Shell.zsh("rm -rf ~/Library/Developer/Xcode/DerivedData/* && echo cleared")
        case .watchman:
            return await Shell.zsh("watchman watch-del-all")
        case .npmCache:
            return await Shell.zsh("npm cache clean --force")
        case .killNode:
            return await Shell.zsh("pkill -x node; echo done")
        default:
            return ShellResult(stdout: "", stderr: "not a maintenance tool", exitCode: -1)
        }
    }
}
