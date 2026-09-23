import Foundation
import Testing
@testable import iLaunch

// Bundle's automatic locale resolution doesn't honor AppleLanguages for
// non-main bundles (verified empirically against the real Sparkle.framework
// in a signed .app — see docs/superpowers/plans). Sparkle's own alerts must
// instead be forced to the right .lproj folder directly.
@Test func sparkleLocalizationFolderMatchesExplicitAppLanguage() {
    #expect(SparkleLocalizationFolder.folderName(for: .chinese, systemLanguageCode: "en") == "zh_CN")
    #expect(SparkleLocalizationFolder.folderName(for: .japanese, systemLanguageCode: "en") == "ja")
    #expect(SparkleLocalizationFolder.folderName(for: .korean, systemLanguageCode: "en") == "ko")
    #expect(SparkleLocalizationFolder.folderName(for: .russian, systemLanguageCode: "en") == "ru")
    #expect(SparkleLocalizationFolder.folderName(for: .english, systemLanguageCode: "zh") == nil)
}

@Test func sparkleLocalizationFolderFollowsSystemLanguageWhenAppLanguageIsSystem() {
    #expect(SparkleLocalizationFolder.folderName(for: .system, systemLanguageCode: "zh") == "zh_CN")
    #expect(SparkleLocalizationFolder.folderName(for: .system, systemLanguageCode: "ja") == "ja")
    #expect(SparkleLocalizationFolder.folderName(for: .system, systemLanguageCode: "ko") == "ko")
    #expect(SparkleLocalizationFolder.folderName(for: .system, systemLanguageCode: "ru") == "ru")
    #expect(SparkleLocalizationFolder.folderName(for: .system, systemLanguageCode: "en") == nil)
    #expect(SparkleLocalizationFolder.folderName(for: .system, systemLanguageCode: "fr") == nil)
}

// Regression (v1.9.2 crash): the swizzle is process-wide, so AppKit calls it
// from background queues too — e.g. NSWorkspace.recycle building a
// localized error on "NSWorkspace background queue" when moving an app to
// the Trash. The lookup must not assume main-actor isolation.
@Test func swizzledLocalizedStringIsSafeOffTheMainThread() async {
    Bundle.activateLanguageOverride()
    let result = await Task.detached {
        Bundle.main.localizedString(forKey: "iLaunchTestKey", value: "fallback", table: nil)
    }.value
    #expect(result == "fallback")
}
