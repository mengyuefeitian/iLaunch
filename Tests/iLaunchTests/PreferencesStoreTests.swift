import Foundation
import Testing
@testable import iLaunch

@Test func defaultPreferencesAreLaunchpadFocused() {
    let preferences = UserPreferences.default
    #expect(preferences.hotKeyCode == 49)
    #expect(preferences.hotKeyModifiers == 2048)
    #expect(preferences.showMenuBarIcon == true)
    #expect(preferences.showDockIcon == true)
    #expect(preferences.overlayDisplayMode == .activeDisplay)
}

@Test func preferencesStoreRoundTripsToDisk() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("preferences.json")
    let store = PreferencesStore(fileStore: JSONFileStore<UserPreferences>(url: url))
    var preferences = UserPreferences.default
    preferences.backgroundBlur = 0.5
    try store.save(preferences)
    #expect(try store.load().backgroundBlur == 0.5)
}

@Test func decodingLegacyPreferencesWithoutHotKeyFieldsUsesOptionSpaceDefault() throws {
    // Simulates a preferences.json written before this feature existed —
    // it has no hotKeyCode/hotKeyModifiers keys at all.
    let legacyJSON = """
    {
        "hotKey": "option+space",
        "launchAtLogin": false,
        "showMenuBarIcon": true,
        "showDockIcon": true,
        "backgroundBlur": 0.72,
        "reduceMotion": false,
        "showSystemApplications": true,
        "overlayDisplayMode": "activeDisplay",
        "scanDirectories": ["/Applications"]
    }
    """
    let decoded = try JSONDecoder.iLaunch.decode(UserPreferences.self, from: Data(legacyJSON.utf8))
    #expect(decoded.hotKeyCode == 49)
    #expect(decoded.hotKeyModifiers == 2048)
}

@Test func hotKeyFieldsRoundTripThroughJSON() throws {
    var preferences = UserPreferences.default
    preferences.hotKeyCode = 40 // kVK_ANSI_K
    preferences.hotKeyModifiers = 256 | 512 // cmdKey | shiftKey
    let data = try JSONEncoder.iLaunch.encode(preferences)
    let decoded = try JSONDecoder.iLaunch.decode(UserPreferences.self, from: data)
    #expect(decoded.hotKeyCode == 40)
    #expect(decoded.hotKeyModifiers == 768)
}

@Test func decodingLegacyPreferencesWithoutDiagLoggingFieldDefaultsToEnabled() throws {
    // Simulates a preferences.json written before the diagnostic-logging
    // toggle existed — it has no diagLoggingEnabled key at all. Must default
    // to true so existing users keep getting logs (unchanged behavior)
    // until they explicitly opt out in Settings.
    let legacyJSON = """
    {
        "hotKeyCode": 49,
        "hotKeyModifiers": 2048,
        "launchAtLogin": false,
        "showMenuBarIcon": true,
        "showDockIcon": true,
        "backgroundBlur": 0.72,
        "reduceMotion": false,
        "showSystemApplications": true,
        "overlayDisplayMode": "activeDisplay",
        "scanDirectories": ["/Applications"]
    }
    """
    let decoded = try JSONDecoder.iLaunch.decode(UserPreferences.self, from: Data(legacyJSON.utf8))
    #expect(decoded.diagLoggingEnabled == true)
}

@Test func diagLoggingEnabledRoundTripsThroughJSON() throws {
    var preferences = UserPreferences.default
    preferences.diagLoggingEnabled = false
    let data = try JSONEncoder.iLaunch.encode(preferences)
    let decoded = try JSONDecoder.iLaunch.decode(UserPreferences.self, from: data)
    #expect(decoded.diagLoggingEnabled == false)
}

@Test func defaultPreferencesDoesNotCoverDock() {
    #expect(UserPreferences.default.coverDock == false)
}

@Test func decodingLegacyPreferencesWithOldHideDockOnLaunchKeyDefaultsToNotCoveringDock() throws {
    // Simulates a preferences.json written by a version that still had the
    // old `hideDockOnLaunch` flag (which every existing user has saved as
    // `true`). The product decision is that everyone gets the new
    // Dock-visible behaviour after upgrading, so the old key must be
    // ignored entirely — not read as a synonym for `coverDock`.
    let legacyJSON = """
    {
        "hotKeyCode": 49,
        "hotKeyModifiers": 2048,
        "launchAtLogin": false,
        "showMenuBarIcon": true,
        "showDockIcon": true,
        "backgroundBlur": 0.72,
        "reduceMotion": false,
        "showSystemApplications": true,
        "overlayDisplayMode": "activeDisplay",
        "scanDirectories": ["/Applications"],
        "hideDockOnLaunch": true
    }
    """
    let decoded = try JSONDecoder.iLaunch.decode(UserPreferences.self, from: Data(legacyJSON.utf8))
    #expect(decoded.coverDock == false)
}

@Test func coverDockRoundTripsThroughJSON() throws {
    var preferences = UserPreferences.default
    preferences.coverDock = true
    let data = try JSONEncoder.iLaunch.encode(preferences)
    let decoded = try JSONDecoder.iLaunch.decode(UserPreferences.self, from: data)
    #expect(decoded.coverDock == true)
}
