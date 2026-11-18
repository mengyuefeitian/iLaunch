import AppKit
import Carbon
import Testing
@testable import iLaunch

@Test func acceptsSingleKeys() {
    #expect(HotKeyCapture.isValid(keyCode: UInt32(kVK_ANSI_K)))
    #expect(HotKeyCapture.isValid(keyCode: UInt32(kVK_F4)))
}

@Test func reservesEscape() {
    #expect(!HotKeyCapture.isValid(keyCode: UInt32(kVK_Escape)))
}

@Test func acceptsOptionSpace() {
    #expect(HotKeyCapture.isValid(keyCode: UInt32(kVK_Space)))
}

@Test func translatesCommandAndOptionModifierFlags() {
    let flags: NSEvent.ModifierFlags = [.command, .option]
    #expect(HotKeyCapture.carbonModifiers(from: flags) == UInt32(cmdKey) | UInt32(optionKey))
}

@Test func translatesNoModifierFlagsToZero() {
    #expect(HotKeyCapture.carbonModifiers(from: []) == 0)
}

@Test func displaysOptionSpace() {
    #expect(HotKeyCapture.displayString(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey)) == "⌥Space")
}

@Test func displaysCommandShiftReturn() {
    let modifiers = UInt32(cmdKey) | UInt32(shiftKey)
    #expect(HotKeyCapture.displayString(keyCode: UInt32(kVK_Return), modifiers: modifiers) == "⇧⌘Return")
}
