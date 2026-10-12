import AppKit

/// Opens or closes the MenuBarExtra popover by clicking its status-bar button, exactly as a
/// mouse click would. SwiftUI has no API for this, so we find the button AppKit made for it.
@MainActor
enum MenuBarPopover {
    static func toggle() {
        guard let button = statusButton() else { return }
        if !isOpen { NSApp.activate(ignoringOtherApps: true) }   // so the popover takes keyboard focus
        button.performClick(nil)
    }

    /// Close the popover if it is open. This goes through the status-bar button rather than
    /// closing the window, because SwiftUI keeps its own "is it open" flag: a window closed
    /// behind its back leaves the flag set, and the next click on the menu-bar icon does nothing.
    static func close() {
        guard isOpen else { return }
        statusButton()?.performClick(nil)
    }

    private static var isOpen: Bool {
        NSApp.windows.contains { $0.isVisible && $0.className.contains("MenuBarExtraWindow") }
    }

    private static func statusButton() -> NSStatusBarButton? {
        for window in NSApp.windows {
            if let button = firstStatusButton(in: window.contentView) { return button }
        }
        return nil
    }

    private static func firstStatusButton(in view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let button = view as? NSStatusBarButton { return button }
        for subview in view.subviews {
            if let button = firstStatusButton(in: subview) { return button }
        }
        return nil
    }
}
