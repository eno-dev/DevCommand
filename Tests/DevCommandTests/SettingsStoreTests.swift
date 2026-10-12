import XCTest
@testable import DevCommand

final class SettingsStoreTests: XCTestCase {
    /// Upgrading keeps the user's order and slots each new tool in beside its neighbours, rather
    /// than dumping new converters at the bottom below the maintenance actions.
    func testReconciledSlotsNewIDsNextToTheirDefaultNeighbour() {
        let defaults = ["uuid", "timestamp", "base64", "urlEncode", "jwt", "sha256", "json", "derivedData", "killNode"]
        let stored = ["uuid", "timestamp", "base64", "jwt", "derivedData", "killNode"]   // saved before the new tools
        XCTAssertEqual(SettingsStore.reconciled(stored, defaults: defaults),
                       ["uuid", "timestamp", "base64", "urlEncode", "jwt", "sha256", "json", "derivedData", "killNode"])
    }

    func testReconciledKeepsACustomOrder() {
        let defaults = ["a", "b", "c", "d"]
        XCTAssertEqual(SettingsStore.reconciled(["c", "a"], defaults: defaults), ["c", "d", "a", "b"])
        XCTAssertEqual(SettingsStore.reconciled(["d", "c", "b", "a"], defaults: defaults), ["d", "c", "b", "a"])
    }

    func testReconciledHandlesEmptyAndLeadingAdditions() {
        XCTAssertEqual(SettingsStore.reconciled([], defaults: ["a", "b"]), ["a", "b"])
        XCTAssertEqual(SettingsStore.reconciled(["b"], defaults: ["a", "b"]), ["a", "b"])   // a new first item leads
    }
}
