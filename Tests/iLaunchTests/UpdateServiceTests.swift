import Foundation
import Testing
@testable import iLaunch

@MainActor
private final class FakeUpdater: UpdaterConfigurable {
    var automaticallyChecksForUpdates = false
    var updateCheckInterval: TimeInterval = 0
}

@Test func desiredConfigurationChecksAutomaticallyOnceDaily() {
    let config = UpdateService.desiredConfiguration
    #expect(config.automaticallyChecksForUpdates == true)
    #expect(config.updateCheckInterval == 86400)
}

@MainActor
@Test func configureAppliesDesiredConfigurationToAnyUpdater() {
    let fake = FakeUpdater()
    UpdateService.configure(fake)
    #expect(fake.automaticallyChecksForUpdates == true)
    #expect(fake.updateCheckInterval == 86400)
}
