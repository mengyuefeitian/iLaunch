import Testing
@testable import iLaunch

@MainActor
@Test func updateCheckDismissesOverlayAndActivatesBeforeChecking() {
    var calls: [String] = []
    MenuBarController.performUpdateCheck(
        dismissOverlay: { calls.append("dismiss") },
        activateApp: { calls.append("activate") },
        check: { calls.append("check") }
    )
    #expect(calls == ["dismiss", "activate", "check"])
}
