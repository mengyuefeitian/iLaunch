import Foundation

/// Persists the user's layout (page arrangement and folders) to Application
/// Support so it survives relaunches.
struct LayoutPersistenceStore {
    private let fileStore: JSONFileStore<LaunchpadLayout>

    init(fileStore: JSONFileStore<LaunchpadLayout>? = nil) {
        if let fileStore {
            self.fileStore = fileStore
        } else {
            let directory: URL
            do {
                directory = try iLaunchPaths.applicationSupportDirectory()
            } catch {
                directory = FileManager.default.temporaryDirectory
                DiagLog.write("LayoutPersistenceStore.init: applicationSupportDirectory() failed (\(error)) — " +
                    "falling back to \(directory.path), which the OS may clear; layout will not survive relaunch")
            }
            self.fileStore = JSONFileStore<LaunchpadLayout>(
                url: directory.appendingPathComponent("layout.json")
            )
        }
    }

    func load() -> LaunchpadLayout {
        do {
            let layout = try fileStore.load(default: .empty)
            DiagLog.write("LayoutPersistenceStore.load: \(fileStore.url.path) -> " +
                "\(layout.pages.flatMap { $0 }.count) page item(s), \(layout.folders.count) folder(s) " +
                "(\(layout.folders.reduce(0) { $0 + $1.items.count }) member(s) total)")
            return layout
        } catch {
            DiagLog.write("LayoutPersistenceStore.load: FAILED reading \(fileStore.url.path) — \(error) " +
                "— falling back to an empty layout")
            return .empty
        }
    }

    func save(_ layout: LaunchpadLayout) {
        do {
            try fileStore.save(layout)
        } catch {
            DiagLog.write("LayoutPersistenceStore.save: FAILED writing \(fileStore.url.path) — \(error) " +
                "— \(layout.folders.count) folder(s) in this layout were NOT persisted")
        }
    }
}
