import Foundation
import Testing
@testable import iLaunch

@Test func scannerReadsMinimalAppBundle() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let appURL = root.appendingPathComponent("Example.app", isDirectory: true)
    let contents = appURL.appendingPathComponent("Contents", isDirectory: true)
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    let plist = contents.appendingPathComponent("Info.plist")
    try """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>CFBundleIdentifier</key>
      <string>com.example.Example</string>
      <key>CFBundleName</key>
      <string>Example</string>
      <key>CFBundleShortVersionString</key>
      <string>2.5</string>
    </dict>
    </plist>
    """.data(using: .utf8)!.write(to: plist)

    let scanner = AppScanner(finderNameProvider: { _ in nil })
    let records = scanner.scan(
        directories: [root],
        now: Date(timeIntervalSince1970: 20)
    )

    #expect(records.count == 1)
    #expect(records[0].id == "bundle:com.example.Example")
    #expect(records[0].name == "Example")
    #expect(records[0].version == "2.5")
    #expect(records[0].isMissing == false)
}

@Test func scannerPrefersFinderDisplayNameOverBundleName() throws {
    let root = try makeSyntheticApp(name: "Example", bundleName: "WeChat")
    // Two identical bundles (e.g. WeChat.app and WeChat2.app) share the same
    // CFBundleDisplayName; only the Finder/Spotlight name keeps them apart.
    let scanner = AppScanner(finderNameProvider: { url in
        url.lastPathComponent == "Example.app" ? "微信" : nil
    })

    let records = scanner.scan(directories: [root], now: Date(timeIntervalSince1970: 20))

    #expect(records.count == 1)
    #expect(records[0].name == "微信")
}

@Test func scannerStripsAppSuffixFromFinderDisplayName() throws {
    let root = try makeSyntheticApp(name: "Example", bundleName: "WeChat")
    let scanner = AppScanner(finderNameProvider: { _ in "WeChat2.app" })

    let records = scanner.scan(directories: [root], now: Date(timeIntervalSince1970: 20))

    #expect(records.count == 1)
    #expect(records[0].name == "WeChat2")
}

@Test func scannerFallsBackToBundleNameWhenFinderNameUnavailable() throws {
    let root = try makeSyntheticApp(name: "Example", bundleName: "FallbackName")
    let scanner = AppScanner(finderNameProvider: { _ in nil })

    let records = scanner.scan(directories: [root], now: Date(timeIntervalSince1970: 20))

    #expect(records.count == 1)
    #expect(records[0].name == "FallbackName")
}

/// Regression test: AppScanner used to silently swallow FileManager errors
/// per directory (`try?`), contributing zero records for that directory with
/// no signal that anything went wrong. A caller merging that into an
/// existing layout (pruneApps) could not tell "this directory legitimately
/// has no apps" from "this directory failed to enumerate" — and treated
/// both the same, wiping any layout entries that happened to live in the
/// failed directory even though every OTHER configured directory scanned
/// fine. The scan must report which directories failed so callers can
/// distinguish the two cases.
@Test func scanReportsFailedDirectoriesWithoutLosingOtherResults() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let appURL = root.appendingPathComponent("Example.app", isDirectory: true)
    let contents = appURL.appendingPathComponent("Contents", isDirectory: true)
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    try """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>CFBundleIdentifier</key>
      <string>com.example.Example</string>
      <key>CFBundleName</key>
      <string>Example</string>
    </dict>
    </plist>
    """.data(using: .utf8)!.write(to: contents.appendingPathComponent("Info.plist"))

    let missingDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("does-not-exist-\(UUID().uuidString)")

    let scanner = AppScanner()
    let result = scanner.scanAll(directories: [root, missingDirectory])

    #expect(result.records.count == 1, "the directory that scanned fine must still contribute its apps")
    #expect(result.failedDirectories == [missingDirectory.path])
}

/// Regression test: unlike the top-level `contentsOfDirectory` calls, the
/// nested `FileManager.enumerator(at:)` calls used to group apps inside a
/// directory-folder (e.g. `/Applications/Python 3.13`) and to walk `/System`
/// trees passed no `errorHandler`. Per Apple's documented behavior, without
/// one, a permission error on a subdirectory silently stops descent into
/// just that subtree — the enumerator returns fewer items with no thrown
/// error and no nil result. That subtree's apps vanished from `records` with
/// nothing recorded in `failedDirectories`, so `applyScanResult`'s safety
/// guard (added in cc80274/0876a08) never caught it: `pruneApps` treated the
/// apps as uninstalled and silently wiped them from the user's folder. This
/// reproduces with a real permission-denied subdirectory (chmod 000).
@Test func scanReportsFailedDirectoryForUnreadableNestedFolder() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer {
        // Restore permissions before cleanup so removal doesn't fail.
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: root.appendingPathComponent("BigFolder").path
        )
        try? FileManager.default.removeItem(at: root)
    }

    let bigFolder = root.appendingPathComponent("BigFolder", isDirectory: true)
    try FileManager.default.createDirectory(at: bigFolder, withIntermediateDirectories: true)
    try makeSyntheticApp(named: "AppB", bundleID: "com.example.AppB", in: bigFolder)
    try makeSyntheticApp(named: "AppC", bundleID: "com.example.AppC", in: bigFolder)

    // Deny read/execute on BigFolder so its contents can't be enumerated —
    // simulating a TCC permission that hasn't fully propagated yet right
    // after granting "App Management" and restarting.
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: bigFolder.path)

    let scanner = AppScanner()
    let result = scanner.scanAll(directories: [root])

    // $TMPDIR is under /var, which FileManager's errorHandler reports
    // resolved to /private/var — compare on the stable suffix instead.
    #expect(
        result.failedDirectories.contains { $0.hasSuffix("/BigFolder") },
        "an unreadable nested folder must be reported as failed, not silently treated as empty"
    )
}

/// Writes a minimal synthetic `.app` bundle named `name` directly inside `directory`.
private func makeSyntheticApp(named name: String, bundleID: String, in directory: URL) throws {
    let appURL = directory.appendingPathComponent("\(name).app", isDirectory: true)
    let contents = appURL.appendingPathComponent("Contents", isDirectory: true)
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    try """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>CFBundleIdentifier</key>
      <string>\(bundleID)</string>
      <key>CFBundleName</key>
      <string>\(name)</string>
    </dict>
    </plist>
    """.data(using: .utf8)!.write(to: contents.appendingPathComponent("Info.plist"))
}

/// Creates a temp directory containing one synthetic `.app` bundle whose
/// `CFBundleName` can differ from the file name.
private func makeSyntheticApp(name: String, bundleName: String) throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let appURL = root.appendingPathComponent("\(name).app", isDirectory: true)
    let contents = appURL.appendingPathComponent("Contents", isDirectory: true)
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    let plist = contents.appendingPathComponent("Info.plist")
    try """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>CFBundleIdentifier</key>
      <string>com.example.\(name)</string>
      <key>CFBundleName</key>
      <string>\(bundleName)</string>
    </dict>
    </plist>
    """.data(using: .utf8)!.write(to: plist)
    return root
}

@Test func scannerFollowsSymlinkedAppBundle() throws {
    // Mirrors /Applications/Safari.app -> ../System/Cryptexes/App/.../Safari.app
    let outside = try makeSyntheticApp(name: "Example", bundleName: "Example")
    let scanned = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: scanned, withIntermediateDirectories: true)
    let link = scanned.appendingPathComponent("Example.app")
    try FileManager.default.createSymbolicLink(
        at: link,
        withDestinationURL: outside.appendingPathComponent("Example.app")
    )

    let scanner = AppScanner(finderNameProvider: { _ in nil })
    let records = scanner.scan(directories: [scanned], now: Date(timeIntervalSince1970: 20))

    #expect(records.count == 1)
    #expect(records.first?.name == "Example")
    // Path stays under the scanned directory (not the symlink target).
    #expect(records.first?.path.hasSuffix("\(scanned.lastPathComponent)/Example.app") == true)
}

@Test func scannerFollowsSymlinkedFolderOfApps() throws {
    let outside = try makeSyntheticApp(name: "One", bundleName: "One")
    try makeSyntheticApp(named: "Two", bundleID: "com.example.Two", in: outside)
    let scanned = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: scanned, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
        at: scanned.appendingPathComponent("Suite"),
        withDestinationURL: outside
    )

    let scanner = AppScanner(finderNameProvider: { _ in nil })
    let result = scanner.scanAll(directories: [scanned], now: Date(timeIntervalSince1970: 20))

    #expect(result.records.count == 2)
    #expect(result.directoryFolders.count == 1)
}
