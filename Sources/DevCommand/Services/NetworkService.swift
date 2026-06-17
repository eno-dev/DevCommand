import Foundation

enum NetworkService {
    /// All usable IPv4 addresses per interface, via `getifaddrs` (no subprocess).
    /// Skips loopback, down interfaces, and link-local (169.254.x.x) addresses.
    static func localAddresses() -> [(interface: String, ip: String)] {
        var results: [(String, String)] = []
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0 else { return [] }
        defer { freeifaddrs(ifaddrPtr) }

        var cursor = ifaddrPtr
        while let ptr = cursor {
            let ifa = ptr.pointee
            cursor = ifa.ifa_next

            guard let sa = ifa.ifa_addr else { continue }
            guard sa.pointee.sa_family == sa_family_t(AF_INET) else { continue }   // IPv4 only

            let flags = Int32(ifa.ifa_flags)
            guard (flags & IFF_UP) == IFF_UP, (flags & IFF_LOOPBACK) == 0 else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let code = getnameinfo(sa, socklen_t(sa.pointee.sa_len),
                                   &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            guard code == 0 else { continue }

            let ip = String(cString: host)
            guard !ip.isEmpty, !ip.hasPrefix("169.254") else { continue }
            results.append((String(cString: ifa.ifa_name), ip))
        }
        return results
    }

    /// Primary LAN IP — prefers the usual Wi-Fi/Ethernet interfaces, else the first found.
    static func primaryLocalIP() -> String? {
        let all = localAddresses()
        for preferred in ["en0", "en1", "en2"] {
            if let match = all.first(where: { $0.interface == preferred }) { return match.ip }
        }
        return all.first?.ip
    }

    /// Public IP — looked up only when the user asks to see it, never on a timer.
    ///
    /// Primary path is a tiny DNS query via `dig` (built into macOS, consistent with how the rest
    /// of the app shells out, and far less revealing than an HTTP request — no headers, no body,
    /// no TLS to a random web endpoint). Falls back to a single plain-text HTTPS service when DNS
    /// is blocked (captive portals, locked-down corporate DNS).
    /// Cached so repeatedly opening the menu (with "Show public IP" on) doesn't re-query each
    /// time; `forceRefresh` (the IP bar's refresh / reveal actions) bypasses it.
    static let publicIPCache = TimedValueCache<String>()

    static func publicIP(forceRefresh: Bool = false) async -> String? {
        if forceRefresh {
            let fresh = await fetchPublicIP()
            if let fresh { await publicIPCache.set(fresh) }
            return fresh
        }
        // Cached 5 min; concurrent callers coalesce onto a single lookup.
        return await publicIPCache.value(ttl: 300) { await fetchPublicIP() }
    }

    /// One public-IP lookup — a DNS query via `dig` (OpenDNS), falling back to a single HTTPS
    /// "what's my IP" service when DNS is blocked.
    private static func fetchPublicIP() async -> String? {
        // `+tries=1`/`+time=3` keep it snappy so we fail over to HTTPS quickly when port 53 is firewalled.
        let dns = await Shell.run("/usr/bin/dig",
                                  ["-4", "+short", "+tries=1", "+time=3",
                                   "myip.opendns.com", "@resolver1.opendns.com"])
        let dnsIP = dns.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if dns.ok, isPlausibleIP(dnsIP) { return dnsIP }

        guard let url = URL(string: "https://api.ipify.org") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        if let (data, response) = try? await URLSession.shared.data(for: request),
           (response as? HTTPURLResponse)?.statusCode == 200 {
            let ip = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if isPlausibleIP(ip) { return ip }
        }
        return nil
    }

    static func isPlausibleIP(_ string: String) -> Bool {
        if string.contains(":") { return true }   // IPv6
        let parts = string.split(separator: ".")
        return parts.count == 4 && parts.allSatisfy { Int($0) != nil }
    }
}
