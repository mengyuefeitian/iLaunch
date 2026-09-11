import Foundation
import Testing
@testable import iLaunch

@Test @MainActor func appleLanguagesOverrideMatchesSparkleFrameworkLocalizations() {
    #expect(Localizer.appleLanguagesOverride(for: .chinese) == ["zh-CN"])
    #expect(Localizer.appleLanguagesOverride(for: .english) == ["en"])
    #expect(Localizer.appleLanguagesOverride(for: .japanese) == ["ja"])
    #expect(Localizer.appleLanguagesOverride(for: .korean) == ["ko"])
    #expect(Localizer.appleLanguagesOverride(for: .russian) == ["ru"])
}

@Test @MainActor func appleLanguagesOverrideIsNilForSystemLanguage() {
    #expect(Localizer.appleLanguagesOverride(for: .system) == nil)
}
