import SwiftUI

@main
struct DevCommandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("DevCommand", systemImage: "shippingbox.fill") {
            RootView()
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}

/// Launch-time setup that can't wait for a view: the popover's content isn't built until it is
/// first opened, and the global shortcut has to work before that.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        GlobalHotKey.shared.apply(Preferences.hotKey)
    }
}
