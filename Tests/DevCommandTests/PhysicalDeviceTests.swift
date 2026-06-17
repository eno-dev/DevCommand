import XCTest
@testable import DevCommand

final class PhysicalDeviceTests: XCTestCase {
    private func device(deviceType: String = "iPhone", platform: String = "iOS",
                        model: String = "", connected: Bool = true, paired: Bool = true,
                        tunnelState: String? = nil, transport: String? = "wired") -> PhysicalDevice {
        PhysicalDevice(identifier: "id", udid: "udid", name: "Phone", model: model,
                       platform: platform, osVersion: "17.0", deviceType: deviceType,
                       pairingState: paired ? "paired" : "unpaired",
                       tunnelState: tunnelState ?? (connected ? "connected" : "unavailable"),
                       transport: transport)
    }

    func testConnectionLabel() {
        XCTAssertEqual(device(transport: "localNetwork").connectionLabel, "Wi-Fi")
        XCTAssertEqual(device(transport: "wired").connectionLabel, "USB")
        XCTAssertEqual(device(transport: "localUSB").connectionLabel, "USB")
        XCTAssertEqual(device(transport: "carrier").connectionLabel, "Connected")
        XCTAssertNil(device(connected: false).connectionLabel)
    }

    func testTVAndWatchDetection() {
        XCTAssertTrue(device(deviceType: "appleTV").isTV)
        XCTAssertTrue(device(deviceType: "x", platform: "tvOS").isTV)
        XCTAssertTrue(device(deviceType: "appleWatch").isWatch)
        XCTAssertTrue(device(deviceType: "x", platform: "watchOS").isWatch)
        XCTAssertFalse(device(deviceType: "iPhone").isTV)
    }

    func testIsRunnable() {
        XCTAssertTrue(device(deviceType: "iPhone", connected: true).isRunnable)
        XCTAssertFalse(device(deviceType: "iPhone", connected: false).isRunnable)   // tunnel unavailable
        XCTAssertFalse(device(deviceType: "appleWatch", connected: true).isRunnable) // watch
        XCTAssertFalse(device(deviceType: "iPhone", paired: false).isRunnable)       // unpaired
    }

    /// Mirrors Expo's exact filter: paired AND tunnel != "unavailable". The real-world
    /// Wi-Fi case is a paired phone sitting at "disconnected" — Expo accepts it, so must we.
    func testPassesExpoFilter() {
        XCTAssertTrue(device(tunnelState: "connected").passesExpoFilter)
        XCTAssertTrue(device(tunnelState: "disconnected").passesExpoFilter)   // idle Wi-Fi tunnel
        XCTAssertFalse(device(tunnelState: "unavailable").passesExpoFilter)   // asleep/locked
        XCTAssertFalse(device(paired: false, tunnelState: "connected").passesExpoFilter)
        // A paired-but-disconnected device is Expo-eligible even though the UI may not call it "connected".
        XCTAssertTrue(device(tunnelState: "disconnected").isConnected)
    }

    func testDisplayModelFallsBackToDeviceType() {
        XCTAssertEqual(device(deviceType: "iPhone", model: "iPhone 17 Pro").displayModel, "iPhone 17 Pro")
        XCTAssertEqual(device(deviceType: "iPad", model: "").displayModel, "iPad")
        XCTAssertEqual(device(deviceType: "appleTV", model: "").displayModel, "Apple TV")
        XCTAssertEqual(device(deviceType: "", model: "").displayModel, "Device")
    }

    func testSymbol() {
        XCTAssertEqual(device(deviceType: "iPad").symbol, "ipad")
        XCTAssertEqual(device(deviceType: "appleTV").symbol, "appletv")
        XCTAssertEqual(device(deviceType: "appleWatch").symbol, "applewatch")
        XCTAssertEqual(device(deviceType: "iPhone").symbol, "iphone")
    }
}
