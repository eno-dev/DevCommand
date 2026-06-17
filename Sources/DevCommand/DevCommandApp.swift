import SwiftUI

@main
struct DevCommandApp: App {
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
