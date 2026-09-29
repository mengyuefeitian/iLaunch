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
