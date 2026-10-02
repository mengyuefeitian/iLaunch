import AppKit
import CoreServices
import Foundation

/// The result of a full scan: every discovered app record plus any on-disk
/// folders that group multiple apps (e.g. `/Applications/Python 3.13`).
struct ScanResult: Equatable {
    var records: [AppRecord]
    var directoryFolders: [DirectoryFolder]
    /// Paths of configured scan directories that could not be enumerated
    /// this pass (permission hiccup, unmounted volume, transient race around
    /// an app install/relaunch, etc). A directory contributing zero records
    /// because it legitimately has none is NOT reported here — only ones
    /// FileManager actually failed to read. Callers must not treat "this
    /// directory failed" the same as "this directory is empty": pruning
    /// layout entries based on a failed directory's absence would delete
    /// real, still-installed apps.
    var failedDirectories: [String] = []
}

struct AppScanner {
    /// Returns the name Finder shows for an app: Spotlight's
    /// `kMDItemDisplayName` with the ".app" suffix removed. Bundle metadata
    /// (`CFBundleDisplayName`) is not enough because duplicate bundles share
    /// it — two WeChat installs both report "WeChat"/"微信" while Finder shows
    /// "微信" and "WeChat2". Injectable so tests stay deterministic.
    var finderNameProvider: @Sendable (URL) -> String? = AppScanner.spotlightDisplayName

    /// Spotlight-backed lookup of the raw Finder display name for a bundle
    /// (e.g. "微信.app"). Returns nil when the file is not indexed yet.
    static let spotlightDisplayName: @Sendable (URL) -> String? = { url in
        guard let item = MDItemCreate(nil, url.path as CFString) else { return nil }
        return MDItemCopyAttribute(item, kMDItemDisplayName) as? String
    }

    /// Resolves the display name for a bundle: the Finder name (with any
    /// ".app" suffix stripped) when available, otherwise the bundle metadata
    /// name.
    private func resolvedName(for appURL: URL, bundleName: String) -> String {
        if let raw = finderNameProvider(appURL) {
            var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.lowercased().hasSuffix(".app") {
                name = String(name.dropLast(4)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if !name.isEmpty { return name }
        }
        return bundleName
    }

    /// Flat list of every discovered app, sorted by display name.
    func scan(directories: [URL], now: Date = Date()) -> [AppRecord] {
        scanAll(directories: directories, now: now).records
    }

    /// Full scan: app records plus detected multi-app directories.
    func scanAll(directories: [URL], now: Date = Date()) -> ScanResult {
        var collected: [AppRecord] = []
        var folderGroups: [(dirURL: URL, memberPaths: [String])] = []
        var failedDirectories: [String] = []

        for directory in directories {
            collect(
                from: directory,
                into: &collected,
                folderGroups: &folderGroups,
                failedDirectories: &failedDirectories,
                now: now
            )
        }

        // Assign stable, unique ids. A bundle identifier is used when it is
        // unique across the scan; when several bundles share one (e.g. IDLE in
        // both Python 3.13 and 3.14) each instance falls back to a path-based
        // id so they stay distinct. Duplicate ids previously produced blank
        // cells because SwiftUI's ForEach requires unique identifiers.
        var bundleIDCounts: [String: Int] = [:]
        for record in collected {
            if let bundleID = record.bundleID {
                bundleIDCounts[bundleID, default: 0] += 1
            }
        }

        var records: [AppRecord] = []
        var pathToID: [String: String] = [:]
        for var record in collected {
            let finalID: String
            if let bundleID = record.bundleID, bundleIDCounts[bundleID] == 1 {
                finalID = "bundle:\(bundleID)"
            } else {
                finalID = "path:\(record.path)"
            }
            record.id = finalID
            record.iconCacheKey = finalID
            pathToID[record.path] = finalID
            records.append(record)
        }

        records.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        var directoryFolders: [DirectoryFolder] = []
        for group in folderGroups {
            let memberIDs = group.memberPaths.compactMap { pathToID[$0] }
            guard memberIDs.count >= 2 else { continue }
            directoryFolders.append(DirectoryFolder(
                id: "dir:\(group.dirURL.path)",
                name: group.dirURL.lastPathComponent,
                path: group.dirURL.path,
                appIDs: memberIDs
            ))
        }
        directoryFolders.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        return ScanResult(records: records, directoryFolders: directoryFolders, failedDirectories: failedDirectories)
    }

    private func collect(
        from directory: URL,
        into collected: inout [AppRecord],
        folderGroups: inout [(dirURL: URL, memberPaths: [String])],
        failedDirectories: inout [String],
        now: Date
    ) {
        // System trees are scanned flat so utilities keep appearing
        // individually, matching the native Launchpad.
        let isSystem = directory.path.hasPrefix("/System")

        if isSystem {
            let subtreeFailures = FailureCollector()
            guard let enumerator = enumeratorReportingFailures(at: directory, into: subtreeFailures) else {
                DiagLog.write("AppScanner.collect: enumerator(at:) returned nil for \(directory.path)")
                failedDirectories.append(directory.path)
                return
            }
            for item in enumerator {
                guard let url = item as? URL, url.pathExtension == "app" else { continue }
                if let record = record(for: url, now: now) {
                    collected.append(record)
                }
            }
            failedDirectories.append(contentsOf: subtreeFailures.paths)
            return
        }

        // Non-system trees are scanned top-level so a directory holding
        // several apps (Python 3.13) can be grouped into a folder, while a
        // directory holding a single app (Adobe Photoshop 2025) just surfaces
        // that app directly.
        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey]
            )
        } catch {
            DiagLog.write("AppScanner.collect: contentsOfDirectory failed for \(directory.path) — \(error)")
            failedDirectories.append(directory.path)
            return
        }

        for entry in entries {
            // Resolve symlinks first: /Applications/Safari.app is a symlink
            // into the cryptex volume, and `.isDirectoryKey` is false for a
            // symlink even when it points at a directory.
            let resolved = entry.resolvingSymlinksInPath()
            let isDirectory = (try? resolved.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDirectory else { continue }

            if entry.pathExtension == "app" {
                if let record = record(for: entry, now: now) {
                    collected.append(record)
                }
            } else {
                var memberPaths: [String] = []
                let subtreeFailures = FailureCollector()
                // Enumerate the resolved directory (the enumerator does not
                // follow a symlinked root) but keep reporting paths under the
                // entry the user sees.
                if let enumerator = enumeratorReportingFailures(at: resolved, into: subtreeFailures) {
                    for item in enumerator {
                        guard let found = item as? URL, found.pathExtension == "app" else { continue }
                        let url = rebase(found, from: resolved, to: entry)
                        if let record = record(for: url, now: now) {
                            collected.append(record)
                            memberPaths.append(url.path)
                        }
                    }
                }
                // A permission error partway through this subdirectory must
                // block pruning of whatever apps it (partially) contributed —
                // the failed subtree may hold more apps we never saw.
                failedDirectories.append(contentsOf: subtreeFailures.paths)
                if !memberPaths.isEmpty {
                    folderGroups.append((entry, memberPaths))
                }
            }
        }
    }

    /// Re-roots `url` (found beneath `root`) so it lives under `newRoot`.
    private func rebase(_ url: URL, from root: URL, to newRoot: URL) -> URL {
        guard root != newRoot else { return url }
        let rootPath = root.path
        guard url.path.hasPrefix(rootPath + "/") else { return url }
        let relative = String(url.path.dropFirst(rootPath.count + 1))
        return newRoot.appendingPathComponent(relative, isDirectory: true)
    }

    /// Wraps `FileManager.enumerator(at:)` with an `errorHandler` so a
    /// permission error partway through a subtree is recorded instead of
    /// silently truncating enumeration (FileManager's default with no
    /// handler: stop descending into the erroring directory and continue
    /// sibling traversal, with no thrown error and no nil result).
    private func enumeratorReportingFailures(
        at url: URL,
        into failures: FailureCollector
    ) -> FileManager.DirectoryEnumerator? {
        FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { errorURL, error in
                DiagLog.write("AppScanner.collect: enumeration error at \(errorURL.path) — \(error)")
                failures.add(errorURL.path)
                return true // keep enumerating sibling entries
            }
        )
    }

    /// Reference-type accumulator so the escaping `errorHandler` closure
    /// (retained by the enumerator for the whole traversal) can record
    /// failures without capturing an `inout` parameter.
    private final class FailureCollector: @unchecked Sendable {
        private(set) var paths: [String] = []
        func add(_ path: String) { paths.append(path) }
    }

    private func record(for appURL: URL, now: Date) -> AppRecord? {
        // `Bundle` understands both macOS bundles (`Contents/Info.plist`) and
        // iOS apps running on Apple Silicon (root `Info.plist`), and exposes
        // the localized display name shown by Finder/Launchpad. Reading the
        // raw plist missed iOS apps entirely and showed generic names such as
        // "MediaCenter" instead of "VidHub".
        if let bundle = Bundle(url: appURL),
           let info = bundle.infoDictionary ?? bundle.localizedInfoDictionary {
            let localized = bundle.localizedInfoDictionary ?? [:]
            let bundleName = displayName(localized: localized, base: info, fallback: appURL.deletingPathExtension().lastPathComponent)
            let name = resolvedName(for: appURL, bundleName: bundleName)
            let version = (info["CFBundleShortVersionString"] as? String)
                ?? (localized["CFBundleShortVersionString"] as? String)
            return AppRecord(
                id: "path:\(appURL.path)",
                bundleID: bundle.bundleIdentifier,
                name: name,
                localizedName: name,
                path: appURL.path,
                iconCacheKey: "path:\(appURL.path)",
                version: version,
                source: source(for: appURL),
                isHidden: false,
                isMissing: false,
                lastSeenAt: now,
                lastLaunchedAt: nil
            )
        }
        return recordViaRawPlist(for: appURL, now: now)
    }

    private func displayName(localized: [String: Any], base: [String: Any], fallback: String) -> String {
        let candidates = [
            localized["CFBundleDisplayName"] as? String,
            base["CFBundleDisplayName"] as? String,
            localized["CFBundleName"] as? String,
            base["CFBundleName"] as? String
        ]
        for candidate in candidates {
            if let value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }
        return fallback
    }

    /// Fallback for bundles `Bundle` cannot read (keeps synthetic test bundles
    /// and unusual layouts working).
    private func recordViaRawPlist(for appURL: URL, now: Date) -> AppRecord? {
        let infoURL = appURL.appendingPathComponent("Contents/Info.plist")
        let data = (try? Data(contentsOf: infoURL))
            ?? (try? Data(contentsOf: appURL.appendingPathComponent("Info.plist")))
        guard let data,
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return nil
        }

        let bundleID = plist["CFBundleIdentifier"] as? String
        let bundleName = displayName(localized: [:], base: plist, fallback: appURL.deletingPathExtension().lastPathComponent)
        let name = resolvedName(for: appURL, bundleName: bundleName)

        return AppRecord(
            id: "path:\(appURL.path)",
            bundleID: bundleID,
            name: name,
            localizedName: name,
            path: appURL.path,
            iconCacheKey: "path:\(appURL.path)",
            version: plist["CFBundleShortVersionString"] as? String,
            source: source(for: appURL),
            isHidden: false,
            isMissing: false,
            lastSeenAt: now,
            lastLaunchedAt: nil
        )
    }

    private func source(for appURL: URL) -> AppRecord.Source {
        if appURL.path.hasPrefix("/System/") { return .systemApplications }
        if appURL.path.hasPrefix(NSHomeDirectory()) { return .userApplications }
        if appURL.path.hasPrefix("/Applications") { return .localApplications }
        return .customDirectory
    }
}
