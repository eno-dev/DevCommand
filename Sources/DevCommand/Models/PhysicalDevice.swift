import Foundation

/// A real, paired device known to CoreDevice — an iPhone, iPad, Apple TV or Watch
/// plugged in or reachable over the local network (as opposed to a `Simulator`).
struct PhysicalDevice: Identifiable, Hashable {
    let identifier: String      // CoreDevice identifier (used by devicectl actions)
    let udid: String            // hardware UDID (provisioning / `run --udid`)
    let name: String            // "Eno's iPhone"
    let model: String           // marketing name, e.g. "iPhone 17 Pro Max" (may be empty)
    let platform: String        // "iOS", "tvOS", "watchOS"
    let osVersion: String       // "26.5.1" (may be empty)
    let deviceType: String      // "iPhone", "iPad", "appleTV", "appleWatch"
    let pairingState: String    // "paired", "unpaired", "" — CoreDevice pairing state
    let tunnelState: String?    // "connected", "disconnected", "unavailable", nil
    let transport: String?      // "localNetwork", "wired", ...

    var id: String { identifier }

    var isTV: Bool { deviceType == "appleTV" || platform == "tvOS" }
    var isWatch: Bool { deviceType == "appleWatch" || platform == "watchOS" }

    /// CoreDevice has a usable connection right now. A live tunnel is anything other than
    /// "unavailable" (or none) — note a paired-over-Wi-Fi device sits at "disconnected" at
    /// rest and still counts, since its tunnel comes up on demand.
    var isConnected: Bool { (tunnelState ?? "unavailable") != "unavailable" }

    /// Exactly Expo CLI's device-eligibility filter — see `@expo/cli`
    /// `AppleDevice.getConnectedDevicesAsync`, which keeps a device only when it is
    /// `pairingState === 'paired' && tunnelState !== 'unavailable'`. A device that fails
    /// this is silently dropped by `expo run:ios`, surfacing as the misleading
    /// "No device UDID or name matching …". We mirror it so DevCommand never hands Expo a
    /// device it would reject.
    var passesExpoFilter: Bool {
        pairingState == "paired" && (tunnelState ?? "unavailable") != "unavailable"
    }

    /// A device we can actually build-and-run an app on from here: Expo would accept it,
    /// and it isn't a watch.
    var isRunnable: Bool { passesExpoFilter && !isWatch }

    /// Friendly model name, falling back to the device type when no marketing name is known.
    var displayModel: String {
        if !model.isEmpty { return model }
        switch deviceType {
        case "iPhone": return "iPhone"
        case "iPad": return "iPad"
        case "appleTV": return "Apple TV"
        case "appleWatch": return "Apple Watch"
        default: return deviceType.isEmpty ? "Device" : deviceType
        }
    }

    /// SF Symbol matching the hardware.
    var symbol: String {
        switch deviceType {
        case "iPad": return "ipad"
        case "appleTV": return "appletv"
        case "appleWatch": return "applewatch"
        default: return "iphone"
        }
    }

    /// Short label for how the device is reached, or nil when not connected.
    var connectionLabel: String? {
        guard isConnected else { return nil }
        switch transport {
        case "localNetwork": return "Wi-Fi"
        case "wired", "usb", "localUSB", "direct": return "USB"
        default: return "Connected"
        }
    }
}
