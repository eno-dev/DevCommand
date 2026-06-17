import XCTest
@testable import DevCommand

final class SimulatorServiceTests: XCTestCase {
    private let json = """
    {
      "devices": {
        "com.apple.CoreSimulator.SimRuntime.iOS-26-5": [
          {"udid":"AAA","name":"iPhone 16","state":"Booted","isAvailable":true},
          {"udid":"BBB","name":"iPhone SE","state":"Shutdown","isAvailable":true},
          {"udid":"CCC","name":"Unavailable","state":"Shutdown","isAvailable":false}
        ],
        "com.apple.CoreSimulator.SimRuntime.tvOS-18-0": [
          {"udid":"DDD","name":"Apple TV 4K","state":"Shutdown","isAvailable":true}
        ]
      }
    }
    """

    func testGroupsByRuntimeAndFiltersUnavailable() {
        let groups = SimulatorService.parse(json)
        XCTAssertEqual(groups.count, 2)

        let ios = groups.first { $0.platform == "iOS" }
        XCTAssertEqual(ios?.version, "26.5")
        XCTAssertEqual(ios?.devices.count, 2)                 // "Unavailable" filtered out
        XCTAssertFalse(ios?.devices.contains { $0.name == "Unavailable" } ?? true)
    }

    func testBootedDeviceSortsFirst() {
        let groups = SimulatorService.parse(json)
        let ios = groups.first { $0.platform == "iOS" }
        XCTAssertEqual(ios?.devices.first?.name, "iPhone 16")
        XCTAssertTrue(ios?.devices.first?.isBooted ?? false)
    }

    func testPlatformOrderAndTVDetection() {
        let groups = SimulatorService.parse(json)
        XCTAssertEqual(groups.first?.platform, "iOS")          // iOS ranks before tvOS
        let tv = groups.first { $0.platform == "tvOS" }
        XCTAssertTrue(tv?.devices.first?.isTV ?? false)
    }

    func testEmptyOnGarbage() {
        XCTAssertTrue(SimulatorService.parse("not json").isEmpty)
    }
}
