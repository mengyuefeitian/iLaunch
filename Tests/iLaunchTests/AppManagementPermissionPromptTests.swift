import Foundation
import Testing
@testable import iLaunch

private func freshDefaults() -> UserDefaults {
    let suiteName = "AppManagementPermissionPromptTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    return defaults
}

@Test func shouldPresentOnFirstEverLaunch() {
    let defaults = freshDefaults()
    #expect(AppManagementPermissionPrompt.shouldPresent(currentVersion: "1.9.9", defaults: defaults) == true)
}

@Test func doesNotPresentAgainForTheSameVersion() {
    let defaults = freshDefaults()
    _ = AppManagementPermissionPrompt.shouldPresent(currentVersion: "1.9.9", defaults: defaults)
    #expect(AppManagementPermissionPrompt.shouldPresent(currentVersion: "1.9.9", defaults: defaults) == false)
}

@Test func presentsAgainAfterVersionChanges() {
    let defaults = freshDefaults()
    _ = AppManagementPermissionPrompt.shouldPresent(currentVersion: "1.9.9", defaults: defaults)
    #expect(AppManagementPermissionPrompt.shouldPresent(currentVersion: "1.9.10", defaults: defaults) == true)
}

@Test func alertTextExplainsLastRegrantAndRemoveReaddStep() {
    let text = AppManagementPermissionPrompt.informativeText
    #expect(text.contains("最后一次"))
    #expect(text.contains("移除"))
}

// MARK: - Launch decision / overlay rule

@Test func overlayIsNotShownAfterUserOpenedSystemSettings() {
    #expect(AppManagementPermissionPrompt.shouldShowOverlay(after: .openedSystemSettings) == false)
    #expect(AppManagementPermissionPrompt.shouldShowOverlay(after: .dismissed) == true)
    #expect(AppManagementPermissionPrompt.shouldShowOverlay(after: .notShown) == true)
}

@Test func alertIsSkippedWhenPermissionAlreadyGranted() {
    #expect(AppManagementPermissionPrompt.shouldShowAlert(status: .granted) == false)
    #expect(AppManagementPermissionPrompt.shouldShowAlert(status: .denied(message: "x")) == true)
    #expect(AppManagementPermissionPrompt.shouldShowAlert(status: .unknown) == true)
}

@MainActor
private func runPrompt(version: String, defaults: UserDefaults, status: PermissionStatus, presented: inout Int, choice: AppManagementPermissionPrompt.Result) async -> AppManagementPermissionPrompt.Result {
    var count = 0
    let result = await AppManagementPermissionPrompt.presentIfNeeded(
        currentVersion: version,
        defaults: defaults,
        probe: { status },
        presenter: { count += 1; return choice }
    )
    presented += count
    return result
}

@MainActor
@Test func grantedProbeSkipsAlertButRecordsVersion() async {
    let defaults = freshDefaults()
    var presented = 0
    let result = await runPrompt(version: "2.0.0", defaults: defaults, status: .granted, presented: &presented, choice: .openedSystemSettings)
    #expect(result == .notShown)
    #expect(presented == 0)
    #expect(AppManagementPermissionPrompt.shouldPresent(currentVersion: "2.0.0", defaults: defaults) == false)
}

@MainActor
@Test func deniedProbePresentsAlertOncePerVersionAndReturnsChoice() async {
    let defaults = freshDefaults()
    var presented = 0
    let first = await runPrompt(version: "2.0.0", defaults: defaults, status: .denied(message: "x"), presented: &presented, choice: .openedSystemSettings)
    #expect(first == .openedSystemSettings)
    let second = await runPrompt(version: "2.0.0", defaults: defaults, status: .denied(message: "x"), presented: &presented, choice: .openedSystemSettings)
    #expect(second == .notShown)
    #expect(presented == 1)
}

@MainActor
@Test func unknownProbeStillPresentsAlert() async {
    let defaults = freshDefaults()
    var presented = 0
    let result = await runPrompt(version: "2.0.0", defaults: defaults, status: .unknown, presented: &presented, choice: .dismissed)
    #expect(result == .dismissed)
    #expect(presented == 1)
}
