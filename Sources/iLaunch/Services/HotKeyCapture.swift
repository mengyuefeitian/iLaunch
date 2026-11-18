import AppKit
import Carbon

/// Pure logic for recording a global hotkey: validating a captured
/// keycode/modifier combo, translating AppKit modifier flags to the Carbon
/// constants `GlobalHotKeyManager` needs, and rendering a display string.
/// Kept separate from `GlobalHotKeyManager` (which owns the live, stateful
/// Carbon registration) so this part is unit-testable without touching any
/// system API.
enum HotKeyCapture {
    static func isValid(keyCode: UInt32) -> Bool {
        keyCode != UInt32(kVK_Escape)
    }

    /// Translates AppKit's modifier flags (captured from the recording
    /// NSEvent monitor) into the Carbon modifier mask `RegisterEventHotKey`
    /// expects.
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    /// Human-readable label, e.g. "⌥Space", "⇧⌘K". Follows real macOS
    /// convention: ⌃⌥⇧⌘ order, with Command last (e.g. Finder's "Save As"
    /// shows "⇧⌘S", not "⌘⇧S").
    static func displayString(keyCode: UInt32, modifiers: UInt32) -> String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        result += keyLabel(for: keyCode)
        return result
    }

    /// Special-cased non-printable keys first (deterministic, no keyboard
    /// layout lookup needed); anything else falls back to the current
    /// keyboard layout via Carbon's UCKeyTranslate so labels are correct
    /// even on non-US layouts.
    private static func keyLabel(for keyCode: UInt32) -> String {
        let special: [Int: String] = [
            kVK_Space: "Space",
            kVK_Return: "Return",
            kVK_Tab: "Tab",
            kVK_Delete: "Delete",
            kVK_ForwardDelete: "⌦",
            kVK_LeftArrow: "←",
            kVK_RightArrow: "→",
            kVK_UpArrow: "↑",
            kVK_DownArrow: "↓",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
            kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
            kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12"
        ]
        if let label = special[Int(keyCode)] { return label }
        return layoutLabel(for: keyCode) ?? "Key\(keyCode)"
    }

    private static func layoutLabel(for keyCode: UInt32) -> String? {
        guard let sourceUnmanaged = TISCopyCurrentKeyboardLayoutInputSource() else { return nil }
        let source = sourceUnmanaged.takeRetainedValue()
        guard let layoutDataPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutDataPointer).takeUnretainedValue() as Data
        return layoutData.withUnsafeBytes { rawPointer -> String? in
            guard let keyLayoutPointer = rawPointer.bindMemory(to: UCKeyboardLayout.self).baseAddress else {
                return nil
            }
            var deadKeyState: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var length = 0
            let status = UCKeyTranslate(
                keyLayoutPointer,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                UInt32(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                chars.count,
                &length,
                &chars
            )
            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: chars, count: length).uppercased()
        }
    }
}
