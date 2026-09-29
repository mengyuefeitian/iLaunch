import AppKit
import Foundation

/// Moves app bundles to the Trash. Deletion is always recoverable: bundles are
/// recycled through the system Trash rather than removed permanently.
protocol AppTrashing: Sendable {
    func moveToTrash(path: String) async -> Bool
}

struct SystemAppTrasher: AppTrashing {
    /// Recycles one path; returns nil on success, otherwise the failure (a
    /// synthetic error when the system reports neither success nor an error).
    typealias Recycler = @Sendable (String) async -> Error?
    /// Asks Finder to trash one path (prompting for an admin password when
    /// needed); returns true only if the bundle is really gone afterwards.
    typealias FinderFallback = @Sendable (String) async -> Bool

    private let recycle: Recycler
    private let finderFallback: FinderFallback

    init(
        recycle: @escaping Recycler = SystemAppTrasher.workspaceRecycle,
        finderFallback: @escaping FinderFallback = SystemAppTrasher.finderTrash
    ) {
        self.recycle = recycle
        self.finderFallback = finderFallback
    }

    func moveToTrash(path: String) async -> Bool {
        guard let error = await recycle(path) else { return true }
        DiagLog.write("moveToTrash failed: path=\(path) \(Self.describe(error))")
        guard Self.needsElevation(error) else { return false }

        DiagLog.write("moveToTrash: falling back to Finder for path=\(path)")
        let success = await finderFallback(path)
        DiagLog.write("moveToTrash: Finder fallback \(success ? "succeeded" : "failed") path=\(path)")
        return success
    }

    // MARK: - Error classification

    /// True for "no permission" failures that Finder can resolve by asking for
    /// an administrator password: NSFileWriteNoPermissionError (513) or a
    /// POSIX EACCES/EPERM, directly or as the underlying error.
    static func needsElevation(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain && ns.code == NSFileWriteNoPermissionError { return true }
        let posixDenied: (NSError) -> Bool = {
            $0.domain == NSPOSIXErrorDomain && ($0.code == Int(EACCES) || $0.code == Int(EPERM))
        }
        if posixDenied(ns) { return true }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError { return posixDenied(underlying) }
        return false
    }

    // MARK: - NSWorkspace

    static let workspaceRecycle: Recycler = { path in
        let url = URL(fileURLWithPath: path)
        return await withCheckedContinuation { continuation in
            NSWorkspace.shared.recycle([url]) { newURLs, error in
                if let error {
                    continuation.resume(returning: error)
                } else if (newURLs ?? [:]).isEmpty {
                    continuation.resume(returning: NSError(
                        domain: "iLaunch.AppTrash", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "recycle returned no new URLs"]))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: - Finder fallback

    /// AppleScript that tells Finder to trash `path`.
    static func finderTrashScript(path: String) -> String {
        "tell application \"Finder\" to delete (POSIX file \"\(escapeForAppleScript(path))\" as alias)"
    }

    /// Escapes backslashes and double quotes for an AppleScript string literal.
    static func escapeForAppleScript(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Threading: NSAppleScript is only safe on the main thread, so the script
    /// runs there. It runs in-process (not via /usr/bin/osascript) so that
    /// iLaunch itself is the Apple Events client and the Automation prompt
    /// names iLaunch. The call blocks the main thread until Finder returns,
    /// i.e. while the user answers the admin-password dialog (owned by Finder);
    /// this is accepted as the price of a working, correctly attributed prompt.
    static let finderTrash: FinderFallback = { path in
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                guard let script = NSAppleScript(source: finderTrashScript(path: path)) else {
                    DiagLog.write("moveToTrash: Finder script could not be created path=\(path)")
                    continuation.resume(returning: false)
                    return
                }
                var errorInfo: NSDictionary?
                script.executeAndReturnError(&errorInfo)
                if let errorInfo {
                    // -128 = user cancelled the password prompt, -1743 = Automation denied.
                    let number = errorInfo[NSAppleScript.errorNumber] ?? "?"
                    let message = errorInfo[NSAppleScript.errorMessage] ?? ""
                    DiagLog.write("moveToTrash: Finder error number=\(number) message=\(message) path=\(path)")
                    continuation.resume(returning: false)
                    return
                }
                continuation.resume(returning: !FileManager.default.fileExists(atPath: path))
            }
        }
    }

    /// Domain, code, description and any underlying error, for the diag log.
    static func describe(_ error: Error?) -> String {
        guard let error else { return "error=nil (recycle returned no new URLs)" }
        let ns = error as NSError
        var text = "error=\(ns.domain)#\(ns.code) \(ns.localizedDescription)"
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
            text += " underlying=\(underlying.domain)#\(underlying.code) \(underlying.localizedDescription)"
        }
        return text
    }
}
