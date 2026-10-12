import XCTest
import AppKit
import Carbon.HIToolbox
@testable import DevCommand

final class HotKeyTests: XCTestCase {
    func testBuildsCarbonModifiersAndLabel() {
        let hotKey = HotKey(keyCode: UInt16(kVK_ANSI_D), flags: [.control, .option, .command], characters: "d")
        XCTAssertEqual(hotKey?.keyCode, UInt32(kVK_ANSI_D))
        XCTAssertEqual(hotKey?.modifiers, UInt32(controlKey | optionKey | cmdKey))
        XCTAssertEqual(hotKey?.display, "⌃⌥⌘D")
    }

    func testNamedKeysGetReadableLabels() {
        XCTAssertEqual(HotKey(keyCode: UInt16(kVK_Space), flags: [.option], characters: " ")?.display, "⌥Space")
        XCTAssertEqual(HotKey(keyCode: UInt16(kVK_F5), flags: [.control, .shift], characters: nil)?.display, "⌃⇧F5")
        XCTAssertEqual(HotKey(keyCode: UInt16(kVK_LeftArrow), flags: [.control, .option], characters: nil)?.display, "⌃⌥←")
    }

    /// A global shortcut takes its keys from every app, so anything without ⌃ or ⌥ is refused:
    /// bare keys, Shift alone, and plain ⌘ combinations like ⌘Q or ⌘C.
    func testRefusesCombinationsThatWouldBreakEverydayKeys() {
        XCTAssertNil(HotKey(keyCode: UInt16(kVK_ANSI_D), flags: [], characters: "d"))
        XCTAssertNil(HotKey(keyCode: UInt16(kVK_ANSI_D), flags: [.shift], characters: "D"))
        XCTAssertNil(HotKey(keyCode: UInt16(kVK_ANSI_Q), flags: [.command], characters: "q"))
        XCTAssertNil(HotKey(keyCode: UInt16(kVK_ANSI_C), flags: [.command, .shift], characters: "c"))
        XCTAssertNil(HotKey(keyCode: UInt16(kVK_Escape), flags: [], characters: nil))
    }
}
