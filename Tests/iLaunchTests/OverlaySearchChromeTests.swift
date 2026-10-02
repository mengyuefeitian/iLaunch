import AppKit
import Testing
@testable import iLaunch

/// Regression: replacing NSTextField's cell with VerticallyCenteredCell must
/// keep the field editable/selectable, otherwise clicks show no caret and
/// keystrokes never insert text.
@MainActor
@Test func searchChromeAllowsTextInputAfterInstall() {
    let chrome = OverlaySearchChrome()
    let parent = NSView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800))
    chrome.install(on: parent) { _ in }

    #expect(chrome.allowsTextInput)
}

/// Search capsule must host Liquid Glass / material frosted background —
/// not a solid opaque fill (regression when AppKit chrome replaced SwiftUI).
@MainActor
@Test func searchChromeUsesGlassBackgroundAfterInstall() {
    let chrome = OverlaySearchChrome()
    let parent = NSView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800))
    chrome.install(on: parent) { _ in }

    #expect(chrome.usesGlassBackground)
}

/// Regression: `container` spans the entire window width at a fixed height
/// to host a much narrower centered search capsule. Plain NSView hit-tests
/// as itself anywhere inside its frame, so every point in that full-width
/// band outside the capsule was silently swallowing clicks meant for
/// whatever's behind it (grid tiles, or a folder popup's backdrop
/// dismiss-tap — reported as needing a dozen-plus clicks on the blank area
/// above an open folder before one landed). Points outside the capsule must
/// fall through (nil); points on the capsule must still hit a real view.
@MainActor
@Test func searchChromeContainerIsClickThroughOutsideCapsule() {
    let chrome = OverlaySearchChrome()
    let parent = NSView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800))
    chrome.install(on: parent) { _ in }

    // Empty region of the top band, well outside the centered 420pt capsule.
    let outsideCapsule = NSPoint(x: 50, y: 700)
    #expect(chrome.view.hitTest(outsideCapsule) == nil)

    // Center of the capsule (chromeHeight 128, fieldHeight 36, topPadding 78
    // place it near the top; container's own frame starts at y = 800 - 128).
    let onCapsule = NSPoint(x: 600, y: 700)
    #expect(chrome.view.hitTest(onCapsule) != nil)
}

@MainActor
@Test func searchChromeSubmitsOnReturnKey() {
    let chrome = OverlaySearchChrome()
    let parent = NSView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800))
    var submitCount = 0
    chrome.install(on: parent, onTextChange: { _ in }, onSubmit: { submitCount += 1 })

    let handled = chrome.control(
        NSTextField(),
        textView: NSTextView(),
        doCommandBy: #selector(NSResponder.insertNewline(_:))
    )

    #expect(handled)
    #expect(submitCount == 1)
}

@MainActor
@Test func searchChromeIgnoresOtherCommands() {
    let chrome = OverlaySearchChrome()
    let parent = NSView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800))
    var submitCount = 0
    chrome.install(on: parent, onTextChange: { _ in }, onSubmit: { submitCount += 1 })

    let handled = chrome.control(
        NSTextField(),
        textView: NSTextView(),
        doCommandBy: #selector(NSResponder.deleteBackward(_:))
    )

    #expect(!handled)
    #expect(submitCount == 0)
}
