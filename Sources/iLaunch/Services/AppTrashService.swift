import AppKit
import Foundation

/// Moves app bundles to the Trash. Deletion is always recoverable: bundles are
/// recycled through the system Trash rather than removed permanently.
protocol AppTrashing: Sendable {
    func moveToTrash(path: String) async -> Bool
}

struct SystemAppTrasher: AppTrashing {
    func moveToTrash(path: String) async -> Bool {
        let url = URL(fileURLWithPath: path)
        return await withCheckedContinuation { continuation in
            NSWorkspace.shared.recycle([url]) { newURLs, error in
                let success = error == nil && !(newURLs ?? [:]).isEmpty
                if !success {
                    DiagLog.write("moveToTrash failed: path=\(path) \(Self.describe(error))")
                }
                continuation.resume(returning: success)
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
