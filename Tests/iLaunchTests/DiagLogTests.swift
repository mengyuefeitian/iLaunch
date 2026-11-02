import Testing
@testable import iLaunch

/// `write()` always no-ops under `swift test` (see `DiagLog.isRunningTests`)
/// so these only cover the on/off switch itself, not actual file writes.

@Test func diagLogDefaultsToEnabled() throws {
    #expect(DiagLog.isEnabled == true)
}

@Test func diagLogConfigureTogglesEnabledState() throws {
    DiagLog.configure(enabled: false)
    #expect(DiagLog.isEnabled == false)

    DiagLog.configure(enabled: true)
    #expect(DiagLog.isEnabled == true)
}

@Test func reversedLinesPutsNewestEntryFirst() throws {
    let text = "[1] a\n[2] b\n[3] c\n"
    #expect(DiagLog.reversedLines(text) == "[3] c\n[2] b\n[1] a\n")
}

@Test func reversedLinesDropsEmptyLinesAndHandlesEmptyInput() throws {
    #expect(DiagLog.reversedLines("a\n\nb\n\n") == "b\na\n")
    #expect(DiagLog.reversedLines("") == "")
}
