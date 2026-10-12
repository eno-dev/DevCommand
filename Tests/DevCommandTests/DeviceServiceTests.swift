import XCTest
@testable import DevCommand

final class DeviceServiceTests: XCTestCase {
    private let json = """
    {
      "result": {
        "devices": [
          {
            "identifier": "id-1",
            "connectionProperties": {"pairingState":"paired","tunnelState":"connected","transportType":"localNetwork"},
            "deviceProperties": {"name":"Eno's iPhone","osVersionNumber":"26.5"},
            "hardwareProperties": {"udid":"UDID1","platform":"iOS","deviceType":"iPhone","marketingName":"iPhone 17 Pro"}
          },
          {
            "identifier": "id-2",
            "connectionProperties": {"pairingState":"paired","tunnelState":"unavailable","transportType":"wired"},
            "deviceProperties": {"name":"Old iPad","osVersionNumber":"17.0"},
            "hardwareProperties": {"udid":"UDID2","platform":"iOS","deviceType":"iPad","marketingName":"iPad"}
          }
        ]
      }
    }
    """

    func testConnectedDeviceSortsFirst() {
        let devices = DeviceService.parse(Data(json.utf8))
        XCTAssertEqual(devices.count, 2)
        XCTAssertEqual(devices.first?.identifier, "id-1")
        XCTAssertTrue(devices.first?.isConnected ?? false)
        XCTAssertEqual(devices.first?.udid, "UDID1")
        XCTAssertEqual(devices.first?.connectionLabel, "Wi-Fi")
        XCTAssertTrue(devices.first?.isRunnable ?? false)
    }

    func testUnavailableTunnelMeansDisconnected() {
        let devices = DeviceService.parse(Data(json.utf8))
        let ipad = devices.first { $0.identifier == "id-2" }
        XCTAssertFalse(ipad?.isConnected ?? true)
        XCTAssertNil(ipad?.connectionLabel)
        XCTAssertFalse(ipad?.isRunnable ?? true)
    }

    func testEmptyOnGarbage() {
        XCTAssertTrue(DeviceService.parse(Data("nope".utf8)).isEmpty)
    }

    /// The real-world Wi-Fi case that started this: a paired phone whose tunnel is idle
    /// ("disconnected", not "unavailable"). Expo accepts it, so it must be runnable.
    func testPairedDisconnectedWifiDeviceIsRunnable() {
        let json = """
        {"result":{"devices":[{
          "identifier":"id-wifi",
          "connectionProperties":{"pairingState":"paired","tunnelState":"disconnected","transportType":"localNetwork"},
          "deviceProperties":{"name":"Eno's iPhone","osVersionNumber":"26.5.1"},
          "hardwareProperties":{"udid":"00008150-000E74802E92401C","platform":"iOS","deviceType":"iPhone","marketingName":"iPhone 17 Pro Max"}
        }]}}
        """
        let device = DeviceService.parse(Data(json.utf8)).first
        XCTAssertEqual(device?.udid, "00008150-000E74802E92401C")
        XCTAssertTrue(device?.passesExpoFilter ?? false)
        XCTAssertTrue(device?.isRunnable ?? false)
    }

    /// An unpaired device is dropped by Expo's filter even if its tunnel is up.
    func testUnpairedDeviceIsNotRunnable() {
        let json = """
        {"result":{"devices":[{
          "identifier":"id-unpaired",
          "connectionProperties":{"pairingState":"unpaired","tunnelState":"connected","transportType":"wired"},
          "deviceProperties":{"name":"Someone's iPhone"},
          "hardwareProperties":{"udid":"UDID9","platform":"iOS","deviceType":"iPhone"}
        }]}}
        """
        let device = DeviceService.parse(Data(json.utf8)).first
        XCTAssertTrue(device?.isConnected ?? false)        // tunnel is up…
        XCTAssertFalse(device?.passesExpoFilter ?? true)   // …but not paired → Expo drops it
        XCTAssertFalse(device?.isRunnable ?? true)
    }

    /// Xcode 26's devicectl reports simulators alongside real devices. They must not show up
    /// under "Physical Devices" (their rows belong to the simulator list, with the same UDID).
    func testSimulatorsAreNotListedAsPhysicalDevices() {
        let mixed = """
        {"result":{"devices":[
          {"identifier":"SIM-UDID",
           "connectionProperties":{"pairingState":"paired","tunnelState":"connected","transportType":"sameMachine"},
           "deviceProperties":{"name":"iPhone 17 Pro Max","osVersionNumber":"26.5"},
           "hardwareProperties":{"udid":"SIM-UDID","platform":"iOS","deviceType":"iPhone","reality":"simulated"}},
          {"identifier":"id-tv",
           "connectionProperties":{"pairingState":"paired","tunnelState":"disconnected","transportType":"localNetwork"},
           "deviceProperties":{"name":"Living Room","osVersionNumber":"27.0"},
           "hardwareProperties":{"udid":"TV-UDID","platform":"tvOS","deviceType":"appleTV","reality":"physical"}},
          {"identifier":"id-phone",
           "connectionProperties":{"pairingState":"paired","tunnelState":"disconnected","transportType":"localNetwork"},
           "deviceProperties":{"name":"Eno's iPhone","osVersionNumber":"26.6.1"},
           "hardwareProperties":{"udid":"PHONE-UDID","platform":"iOS","deviceType":"iPhone"}}
        ]}}
        """
        let devices = DeviceService.parse(Data(mixed.utf8))
        XCTAssertEqual(devices.map(\.name), ["Eno's iPhone", "Living Room"])   // no "reality" field still counts as real
    }
}
