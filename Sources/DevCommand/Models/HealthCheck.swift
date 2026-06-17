import Foundation

/// One environment health result shown in the Doctor panel.
struct HealthCheck: Identifiable {
    enum Status { case ok, warn, fail }

    let id: String
    let title: String
    var detail: String
    var status: Status
    var fixLabel: String?     // e.g. "Install", "Clear"
    var fixCommand: String?   // shell command run in Terminal when the fix is tapped
}
