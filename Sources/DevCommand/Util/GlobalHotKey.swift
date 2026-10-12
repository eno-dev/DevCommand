import AppKit
import Carbon.HIToolbox

/// A global keyboard shortcut: a virtual key code plus Carbon modifier flags, and the label to
/// show for it (e.g. "⌃⌥⌘D").
struct HotKey: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var display: String

    /// Build a shortcut from a key press. Returns nil unless ⌃ or ⌥ is held: a global shortcut
    /// takes its keys away from every other app, so bare keys, Shift alone, and plain ⌘ combos
    /// (⌘Q, ⌘C, ⌘W…) are refused rather than letting a slip of the hand break them system-wide.
    init?(keyCode: UInt16, flags: NSEvent.ModifierFlags, characters: String?) {
        guard !flags.intersection([.control, .option]).isEmpty else { return nil }
        var carbon: UInt32 = 0
        var symbols = ""
        if flags.contains(.control) { carbon |= UInt32(controlKey); symbols += "⌃" }
        if flags.contains(.option) { carbon |= UInt32(optionKey); symbols += "⌥" }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey); symbols += "⇧" }
        if flags.contains(.command) { carbon |= UInt32(cmdKey); symbols += "⌘" }
        self.init(keyCode: UInt32(keyCode), modifiers: carbon,
                  display: symbols + Self.keyLabel(keyCode: keyCode, characters: characters))
    }

    init(keyCode: UInt32, modifiers: UInt32, display: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.display = display
    }

    /// A readable name for the key: named keys by code, everything else by the character it types.
    static func keyLabel(keyCode: UInt16, characters: String?) -> String {
        switch Int(keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_Escape: return "⎋"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default: break
        }
        let functionKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6,
                            kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12]
        if let index = functionKeys.firstIndex(of: Int(keyCode)) { return "F\(index + 1)" }
        let typed = (characters ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return typed.isEmpty ? "Key \(keyCode)" : typed
    }
}

/// Registers the system-wide shortcut that opens (or closes) the menu-bar popover from any app.
/// Carbon hot keys are the one API that delivers a global shortcut without asking for
/// Accessibility or Input Monitoring permission, and they cost nothing until the keys are pressed.
@MainActor
final class GlobalHotKey {
    static let shared = GlobalHotKey()
    private var registration: EventHotKeyRef?
    private var handlerInstalled = false

    /// Register `hotKey`, replacing whatever was registered before; nil turns the shortcut off.
    /// Returns false when the system refuses the combination (already claimed, or reserved).
    @discardableResult
    func apply(_ hotKey: HotKey?) -> Bool {
        if let registration { UnregisterEventHotKey(registration) }
        registration = nil
        guard let hotKey else { return true }
        installHandlerIfNeeded()
        let id = EventHotKeyID(signature: 0x4456_4344, id: 1)   // 'DVCD'
        let status = RegisterEventHotKey(hotKey.keyCode, hotKey.modifiers, id,
                                         GetApplicationEventTarget(), 0, &registration)
        return status == noErr
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { MenuBarPopover.toggle() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
