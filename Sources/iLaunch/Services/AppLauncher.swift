import AppKit
import Foundation

enum LaunchResult: Equatable {
    case launched
    case missingPath
    case failed
}

protocol WorkspaceLaunching {
    func openApplication(at url: URL) -> Bool
}

struct SystemWorkspaceLauncher: WorkspaceLaunching {
    func openApplication(at url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }
}

struct AppLauncher {
    @MainActor
    static func openAsynchronously(_ record: AppRecord) {
        DiagLog.write("App launch requested: \(record.bundleID ?? "unknown")")
        let url = URL(fileURLWithPath: record.path)
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { app, error in
            if let error = error as NSError? {
                DiagLog.write("App launch failed: \(error.domain) (\(error.code))")
            } else {
                DiagLog.write("App launch completed: \(app?.bundleIdentifier ?? "unknown")")
            }
        }
    }

    let workspace: WorkspaceLaunching

    init(workspace: WorkspaceLaunching = SystemWorkspaceLauncher()) {
        self.workspace = workspace
    }

    func launch(_ record: AppRecord) -> LaunchResult {
        guard FileManager.default.fileExists(atPath: record.path) else {
            return .missingPath
        }

        let opened = workspace.openApplication(at: URL(fileURLWithPath: record.path))
        return opened ? .launched : .failed
    }
}
