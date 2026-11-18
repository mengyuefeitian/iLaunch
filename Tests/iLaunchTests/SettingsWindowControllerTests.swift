import AppKit
import Testing
@testable import iLaunch

@MainActor
@Test func settingsWindowUsesStandardContentCoordinates() {
    let mask = SettingsWindowController.windowStyleMask
    #expect(!mask.contains(.fullSizeContentView))
    #expect(mask.contains(.titled))
    #expect(mask.contains(.closable))
    #expect(mask.contains(.resizable))
}
