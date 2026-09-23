import AppKit
import Testing
@testable import iLaunch

@Test func dockVisiblePresentationSitsJustBelowTheDockAndAutoHidesTheMenuBar() {
    let level = OverlayPresentation.windowLevel(coverDock: false)
    #expect(level.rawValue == Int(CGWindowLevelForKey(.dockWindow)) - 1)

    let options = OverlayPresentation.presentationOptions(coverDock: false)
    #expect(options == [.autoHideMenuBar])
}

@Test func coverDockPresentationSitsAboveTheMenuBarWithNoPresentationOptions() {
    let level = OverlayPresentation.windowLevel(coverDock: true)
    #expect(level.rawValue == Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)

    let options = OverlayPresentation.presentationOptions(coverDock: true)
    #expect(options == [])
}
