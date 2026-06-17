import Foundation

enum PortService {
    /// Lists listening TCP ports via `lsof` field output (`-F`), which is robust against
    /// spaces in command names that would break column splitting.
    static func listening() async -> [ListeningPort] {
        let result = await Shell.run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-FpcnL"])
        return parse(result.stdout)
    }

    /// Parse lsof `-F pcnL` output. Each process emits `p<pid>`, `c<command>`, `L<user>`,
    /// then one `n<addr:port>` line per listening socket.
    static func parse(_ output: String) -> [ListeningPort] {
        var pid = 0
        var command = ""
        var user = ""
        var byKey: [String: ListeningPort] = [:]

        for rawLine in output.split(separator: "\n") {
            guard let tag = rawLine.first else { continue }
            let value = String(rawLine.dropFirst())
            switch tag {
            case "p": pid = Int(value) ?? 0
            case "c": command = value
            case "L": user = value
            case "n":
                guard let parsed = parseAddress(value) else { continue }
                let key = "\(pid):\(parsed.port)"
                if let existing = byKey[key] {
                    // Merge IPv4/IPv6 duplicates for the same pid+port; prefer the broadest address.
                    if parsed.address == "*" && existing.address != "*" {
                        byKey[key] = ListeningPort(port: parsed.port, pid: pid,
                                                   command: command, user: user, address: "*")
                    }
                } else {
                    byKey[key] = ListeningPort(port: parsed.port, pid: pid,
                                               command: command, user: user, address: parsed.address)
                }
            default:
                break
            }
        }

        return byKey.values.sorted { lhs, rhs in
            if lhs.isDev != rhs.isDev { return lhs.isDev }   // dev ports first
            return lhs.port < rhs.port
        }
    }

    /// "*:8081" -> ("*", 8081); "127.0.0.1:5432" -> ("127.0.0.1", 5432); "[::1]:5432" -> ("::1", 5432)
    private static func parseAddress(_ name: String) -> (address: String, port: Int)? {
        guard let colon = name.lastIndex(of: ":") else { return nil }
        guard let port = Int(name[name.index(after: colon)...]) else { return nil }
        var address = String(name[..<colon])
        if address.hasPrefix("[") && address.hasSuffix("]") {
            address = String(address.dropFirst().dropLast())
        }
        return (address.isEmpty ? "*" : address, port)
    }

    @discardableResult
    static func kill(pid: Int, force: Bool) async -> ShellResult {
        let signal = force ? "-9" : "-15"
        return await Shell.run("/bin/kill", [signal, "\(pid)"])
    }
}
