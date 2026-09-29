import Foundation
import Testing
@testable import iLaunch

private func makeChecker(_ result: Int32?) -> AppManagementPermissionChecker {
    AppManagementPermissionChecker(preflight: { result })
}

@Test func preflightZeroMeansGranted() {
    #expect(makeChecker(0).check() == .granted)
}

@Test func preflightOneMeansDenied() {
    guard case .denied = makeChecker(1).check() else {
        Issue.record("expected .denied")
        return
    }
}

@Test func preflightTwoMeansUnknown() {
    #expect(makeChecker(2).check() == .unknown)
}

@Test func otherPreflightValuesAreUnknown() {
    for value: Int32 in [-1, 3, 42] {
        #expect(makeChecker(value).check() == .unknown, "value \(value)")
    }
}

@Test func missingSymbolMeansUnknown() {
    #expect(makeChecker(nil).check() == .unknown)
}

@Test func timeoutTreatsSlowPreflightAsUnknown() async {
    let checker = AppManagementPermissionChecker(preflight: {
        Thread.sleep(forTimeInterval: 1.0)
        return 0
    })
    #expect(await checker.check(timeout: 0.1) == .unknown)
}

@Test func asyncCheckReturnsPreflightResultWhenFast() async {
    #expect(await makeChecker(0).check(timeout: 2) == .granted)
    if case .denied = await makeChecker(1).check(timeout: 2) {} else { Issue.record("expected .denied") }
}

@Test func deepLinkPointsAtAppManagementPane() {
    #expect(AppManagementPermissionChecker.systemSettingsURL.absoluteString
        == "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles")
}

@Test func livePreflightDoesNotCrash() {
    // Result depends on the machine's TCC state; only the contract matters.
    _ = AppManagementPermissionChecker.livePreflight()
}
