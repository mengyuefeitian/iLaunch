import Foundation
import Testing
@testable import iLaunch

@Test func iconSizeLevelMultipliersAreBoostedByTenPercent() {
    #expect(UserPreferences.IconSizeLevel.small.multiplier == 0.715)
    #expect(UserPreferences.IconSizeLevel.medium.multiplier == 0.88)
    #expect(UserPreferences.IconSizeLevel.large.multiplier == 1.1)
}
