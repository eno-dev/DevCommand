import Foundation

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
