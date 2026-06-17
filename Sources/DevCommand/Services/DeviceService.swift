import Foundation

/// Lists real, paired devices via `xcrun devicectl` (Xcode's CoreDevice tool).
/// `devicectl` writes its JSON to a file rather than stdout, so we hand it a temp path
/// and parse that. Returns [] cleanly when CoreDevice is unavailable or no device is paired.
enum DeviceService {
    static func list() async -> [PhysicalDevice] {
        let file = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("devcommand-devices-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(atPath: file) }

        let result = await Shell.run("/usr/bin/xcrun",
                                     ["devicectl", "list", "devices", "--json-output", file])
        guard result.ok, let data = FileManager.default.contents(atPath: file) else { return [] }
        return parse(data)
    }

    // MARK: Parsing

    private struct Output: Decodable {
        let result: ResultBlock
        struct ResultBlock: Decodable { let devices: [DeviceDTO] }
    }
    private struct DeviceDTO: Decodable {
        let identifier: String
        let connectionProperties: ConnectionProps?
        let deviceProperties: DeviceProps?
        let hardwareProperties: HardwareProps?

        struct ConnectionProps: Decodable {
            let pairingState: String?
            let tunnelState: String?
            let transportType: String?
        }
        struct DeviceProps: Decodable {
            let name: String?
            let osVersionNumber: String?
        }
        struct HardwareProps: Decodable {
            let udid: String?
            let platform: String?
            let deviceType: String?
            let marketingName: String?
        }
    }

    static func parse(_ data: Data) -> [PhysicalDevice] {
        guard let root = try? JSONDecoder().decode(Output.self, from: data) else { return [] }

        let devices = root.result.devices.map { dto -> PhysicalDevice in
            let hw = dto.hardwareProperties
            let conn = dto.connectionProperties
            // Carry the raw CoreDevice states through; `PhysicalDevice` derives connectivity
            // and Expo eligibility from them (mirroring `expo run:ios`'s own filter).
            return PhysicalDevice(
                identifier: dto.identifier,
                udid: hw?.udid ?? dto.identifier,
                name: dto.deviceProperties?.name ?? "Unknown device",
                model: hw?.marketingName ?? "",
                platform: hw?.platform ?? "",
                osVersion: dto.deviceProperties?.osVersionNumber ?? "",
                deviceType: hw?.deviceType ?? "",
                pairingState: conn?.pairingState ?? "",
                tunnelState: conn?.tunnelState,
                transport: conn?.transportType
            )
        }

        // Connected first, then by platform, then by name — so a plugged-in phone leads.
        return devices.sorted { lhs, rhs in
            if lhs.isConnected != rhs.isConnected { return lhs.isConnected }
            let lp = platformRank(lhs.platform), rp = platformRank(rhs.platform)
            if lp != rp { return lp < rp }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private static func platformRank(_ platform: String) -> Int {
        switch platform {
        case "iOS": return 0
        case "tvOS": return 1
        case "watchOS": return 2
        default: return 9
        }
    }
}
