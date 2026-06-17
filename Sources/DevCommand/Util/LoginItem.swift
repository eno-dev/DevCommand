import Foundation
import ServiceManagement

/// Wraps the modern login-item API (macOS 13+). Registers DevCommand itself as a
/// launch-at-login item — no helper bundle required.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            NSLog("DevCommand: launch-at-login toggle failed: \(error.localizedDescription)")
        }
    }
}
