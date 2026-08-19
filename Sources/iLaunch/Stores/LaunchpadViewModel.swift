import AppKit
import Foundation
import Observation

struct LaunchpadDisplayItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case app(AppRecord)
        case folder(LaunchpadFolder)
    }

    var id: String
    var title: String
    var kind: Kind
    var members: [AppRecord] = []
    var isHiddenApp: Bool = false
}

@MainActor
@Observable
final class LaunchpadViewModel {
    var searchText = ""
    var selectedItemID: String?

    /// When true, tiles jiggle and can be dragged to reorder.
    var editMode = false

    /// The ID of the tile currently being dragged in edit mode (nil if not dragging).
    var editDragID: String?

    /// Translation of the current edit-mode drag.
    var editDragTranslation: CGSize = .zero

    /// Frames of all interactive tile views in the overlay's content-view
    /// coordinate space (origin top-left). Updated via PreferenceKey from
    /// LaunchpadGridView. Includes tile identity so the edit-mode drag can
    /// detect overlap with folder tiles.
    var tileFrames: [TileFrameInfo] = []

    /// Same identities as `tileFrames`, but each frame is the tile's actual
    /// clickable region (icon+title bounds, or an enlarged folder's visible
    /// chrome) rather than the full layout slot. AppKit's first-click
    /// recovery must hit-test against this — see `TileActiveFramePreferenceKey`.
    var tileActiveFrames: [TileFrameInfo] = []

    /// True once the PreferenceKey has reported at least one batch of tile
    /// frames. Before this, dismiss monitors default to "allow" (pass the
    /// click through) so the first click after overlay-open is never eaten
    /// by a premature empty-space dismiss.
    var tileFramesReady = false

    /// The currently-open folder popup, if any. Lives on the @Observable
    /// model (not @State in ContentView) so the NSEvent click monitor
    /// closure can read it by reference — @State in a struct is invisible
    /// inside captured closures.
    var openFolder: LaunchpadDisplayItem?

    /// Grid-tile frame (overlay coords) captured when the folder was opened —
    /// drives zoom-from-tile / zoom-back-to-tile animation.
    var openFolderSourceFrame: CGRect = .zero

    /// Bumped by `requestCloseFolder()` so `FolderPopupView` can play the
    /// scale-out animation before `finishClosingFolder()` clears `openFolder`.
    private(set) var folderCloseEpoch: Int = 0

    /// True while FolderPopupView is playing the close zoom. A second close
    /// request (Esc / blank click) force-finishes so a stuck animation cannot
    /// freeze the overlay forever.
    var isFolderClosing = false

    /// Open a folder popup, remembering where the grid tile sat for zoom animation.
    func openFolderPopup(_ item: LaunchpadDisplayItem) {
        // Always clear any prior open/close first. Stale close timers must not
        // run against the new popup (they used to nil a freshly opened folder).
        if openFolder != nil || isFolderClosing {
            DiagLog.write(
                "openFolderPopup: clearing previous openFolder=\(openFolder?.id ?? "nil") closing=\(isFolderClosing)"
            )
            finishClosingFolder()
        }
        let frame = tileFrames.first(where: { $0.id == item.id })?.frame ?? .zero
        openFolderSourceFrame = frame
        DiagLog.write(
            "openFolderPopup id=\(item.id) members=\(item.members.count) sourceFrame=\(NSStringFromRect(frame))"
        )
        openFolder = item
    }

    /// Ask the open folder popup to animate closed. No-op if nothing is open.
    /// Second call while already closing force-finishes (recovery from hang).
    func requestCloseFolder() {
        guard openFolder != nil else { return }
        if isFolderClosing {
            DiagLog.write("requestCloseFolder: already closing — force finish")
            finishClosingFolder()
            return
        }
        // Refresh source frame so close can target the tile's current position
        // (page may have flipped / layout shifted while the popup was open).
        if let id = openFolder?.id,
           let live = tileFrames.first(where: { $0.id == id })?.frame,
           live.width > 1, live.height > 1 {
            openFolderSourceFrame = live
        }
        isFolderClosing = true
        DiagLog.write("requestCloseFolder id=\(openFolder?.id ?? "?") epoch→\(folderCloseEpoch &+ 1)")
        folderCloseEpoch &+= 1
    }

    /// Called after the close animation finishes (or immediately when animation is off).
    func finishClosingFolder() {
        if openFolder != nil || isFolderClosing || folderPanelFrame != .zero {
            DiagLog.write("finishClosingFolder id=\(openFolder?.id ?? "nil")")
        }
        // Bump epoch so any in-flight FolderPopupView close timer/watchdog
        // becomes a no-op (must not finish-close a *newer* open).
        folderCloseEpoch &+= 1
        openFolder = nil
        openFolderSourceFrame = .zero
        folderPanelFrame = .zero
        isFolderClosing = false
    }

    /// Only finish if this folder is still the one open (guards stale asyncAfter).
    func finishClosingFolderIfOpen(id: String) {
        guard openFolder?.id == id else {
            DiagLog.write("finishClosingFolderIfOpen skip stale id=\(id) current=\(openFolder?.id ?? "nil")")
            return
        }
        finishClosingFolder()
    }

    /// Mirrors FolderPopupView's internal `panelFrame` (overlay coordinate
    /// space, origin top-left). The click monitor uses this to tell blank
    /// backdrop clicks (outside the panel — dismiss) from clicks that must
    /// reach SwiftUI (member taps, reorder, drag-out — inside the panel).
    var folderPanelFrame: CGRect = .zero

    /// The page currently displayed in the grid. Updated by LaunchpadGridView
    /// so drag-out from a folder can insert on the page the user is viewing.
    var currentPage = 0

    var showSystemApplications: Bool = true
    var showHiddenInSearch: Bool = true

    /// App extracted from a folder mid-drag — follows the pointer as a floating
    /// ghost until drop resolves insert / merge. Also set for app grid handoff.
    var floatingDragApp: AppRecord?

    /// Grid item id (app **or folder**) currently tracked by AppKit floating drag
    /// after edge page-flip handoff / folder drag-out.
    var floatingDragItemID: String? = nil

    /// Absolute pointer position in the overlay coordinate space for the ghost.
    var floatingDragPoint: CGPoint = .zero

    /// Tile under the pointer during drag that would receive create/join-folder.
    /// Set by grid drag (via callback) or floating drag-out updates.
    var mergeTargetID: String? = nil

    /// The item currently being live-reorder-dragged on the main grid (for overlay rendering).
    var gridDragItem: LaunchpadDisplayItem?

    /// Absolute pointer position in overlay coordinate space during grid drag.
    var gridDragLocation: CGPoint = .zero

    /// Chains overlapping `bootstrapScan()` calls so each one's read-modify-
    /// write of `layout.json` starts only after the previous one's write
    /// finished — see `bootstrapScan()` for why this matters.
    private var scanQueueTail: Task<Void, Never>?

    private var appIndex: AppIndexStore
    private var layoutStore: LayoutStore
    private let matcher: SearchMatcher
    private let launcher: AppLauncher
    private let scanner: AppScanner
    private let preferencesStore: PreferencesStore
    private let layoutPersistence: LayoutPersistenceStore
    private let trasher: AppTrashing
    private let screenHeight: CGFloat

    var preferences: UserPreferences

    /// Rows per page: user-configured (4/5/6) or auto from screen height.
    var gridRows: Int {
        GridMetrics.effectiveRows(preference: preferences.gridRows, screenHeight: screenHeight)
    }

    /// Columns per page: user-configured, clamped to 6–10.
    var gridColumns: Int {
        GridMetrics.effectiveColumns(preference: preferences.gridColumns)
    }

    init(
        appIndex: AppIndexStore = AppIndexStore(),
        layoutStore: LayoutStore = LayoutStore(),
        matcher: SearchMatcher = SearchMatcher(),
        launcher: AppLauncher = AppLauncher(),
        scanner: AppScanner = AppScanner(),
        preferencesStore: PreferencesStore = PreferencesStore(),
        layoutPersistence: LayoutPersistenceStore = LayoutPersistenceStore(),
        trasher: AppTrashing = SystemAppTrasher(),
        screenHeight: CGFloat = NSScreen.main?.frame.height ?? 1080
    ) {
        self.appIndex = appIndex
        self.layoutStore = layoutStore
        self.matcher = matcher
        self.launcher = launcher
        self.scanner = scanner
        self.preferencesStore = preferencesStore
        self.layoutPersistence = layoutPersistence
        self.trasher = trasher
        self.screenHeight = screenHeight
        self.preferences = (try? preferencesStore.load()) ?? .default
    }

    var visiblePages: [[LaunchpadDisplayItem]] {
        let recordsByID = appIndex.records

        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let hiddenIDs = layoutStore.layout.hiddenAppIDs
            return [matcher.ranked(query: searchText, records: Array(recordsByID.values))
                .filter { record in
                    if record.isMissing { return false }
                    if hiddenIDs.contains(record.id) && !showHiddenInSearch { return false }
                    if !showSystemApplications && Self.isSystemApp(record) { return false }
                    return true
                }
                .map { LaunchpadDisplayItem(id: $0.id, title: $0.name, kind: .app($0), isHiddenApp: hiddenIDs.contains($0.id)) }]
        }

        return layoutStore.layout.pages.map { page in
            page.compactMap { item in
                switch item {
                case .app(let id):
                    guard let record = recordsByID[id], !record.isMissing else { return nil }
                    if layoutStore.layout.hiddenAppIDs.contains(id) { return nil }
                    if !showSystemApplications && Self.isSystemApp(record) { return nil }
                    return LaunchpadDisplayItem(id: id, title: record.name, kind: .app(record))
                case .folder(let id):
                    guard let folder = layoutStore.layout.folders.first(where: { $0.id == id }) else { return nil }
                    if !showSystemApplications && id == LayoutStore.appleFolderID { return nil }
                    var members = folder.items
                        .compactMap { recordsByID[$0] }
                        .filter { !layoutStore.layout.hiddenAppIDs.contains($0.id) && !$0.isMissing }
                    if !showSystemApplications {
                        members = members.filter { !Self.isSystemApp($0) }
                        if members.isEmpty { return nil }
                    }
                    return LaunchpadDisplayItem(id: id, title: folder.name, kind: .folder(folder), members: members)
                }
            }
        }
    }

    /// Whether the current layout has anything a scan could prune — used to
    /// detect a scan that came back suspiciously empty.
    private var layoutHasContent: Bool {
        layoutStore.layout.pages.contains { !$0.isEmpty } || !layoutStore.layout.folders.isEmpty
    }

    func applyScanResult(_ result: ScanResult) {
        // AppScanner reports directories it failed to enumerate (a
        // moved/locked directory, an unmounted volume, a transient glitch
        // around a reinstall) instead of silently pretending they're empty.
        // Two failure shapes must be guarded against separately:
        //  - Any directory failing must not prune at all — apps that live
        //    only in that directory would be treated as uninstalled and
        //    dropped from every folder/page referencing them, even though
        //    the OVERALL result looks fine because other directories still
        //    scanned successfully.
        //  - A scan that found nothing anywhere must never overwrite a
        //    non-empty layout (pruneApps(notIn: []) would wipe every page
        //    and folder in one pass).
        guard result.failedDirectories.isEmpty else {
            DiagLog.write("applyScanResult: directories failed to scan (\(result.failedDirectories.joined(separator: ", "))) — skipping to avoid wiping user data for apps that live there")
            return
        }
        guard !result.records.isEmpty || !layoutHasContent else {
            DiagLog.write("applyScanResult: scan returned 0 apps while the layout has \(layoutStore.layout.folders.count) folder(s) — skipping to avoid wiping user data")
            return
        }
        appIndex.merge(scanResults: result.records)
        layoutStore.syncDirectoryFolders(result.directoryFolders)
        layoutStore.pruneApps(notIn: Set(result.records.map(\.id)))

        // Collect Apple's own apps into the managed "Apple" folder before adding
        // the rest to the grid, so freshly installed Apple apps land in the
        // folder rather than on a page. Apps already placed (on a page or in a
        // folder) are left where they are; appendNewApps skips anything already
        // foldered, so foldered Apple apps don't also land on the grid (a lone
        // Apple app below the folder threshold still appears normally).
        let appleIDs = result.records
            .filter { $0.bundleID?.hasPrefix("com.apple.") == true }
            .map(\.id)
        layoutStore.syncAppleFolder(appleAppIDs: appleIDs)

        let folderMemberIDs = Set(result.directoryFolders.flatMap(\.appIDs))
        let topLevelIDs = result.records.map(\.id).filter {
            !folderMemberIDs.contains($0)
        }
        layoutStore.appendNewApps(topLevelIDs)

        // Clean up folders that have been depleted (0 or 1 members) —
        // removes historical empty folders and dissolves single-app folders.
        layoutStore.dissolveEmptyFolders()
    }

    func launchSelected() -> LaunchResult? {
        guard let selectedItemID,
              let item = visiblePages.flatMap({ $0 }).first(where: { $0.id == selectedItemID }),
              case .app(let record) = item.kind else {
            return nil
        }
        return launcher.launch(record)
    }

    /// Scans installed apps and applies the result to the grid.
    ///
    /// The scan (filesystem enumeration + a synchronous Spotlight lookup per
    /// app) used to run inline on the MainActor, freezing the overlay
    /// (unresponsive to Esc/click, blank render) for its whole duration —
    /// worst after a permission change unlocks scanning many more
    /// directories/apps than usual. It now runs on a background task and
    /// only hops back to the MainActor to apply the result.
    ///
    /// The overlay re-triggers this on every show (a fresh `ContentView`,
    /// hence a fresh `.task`), so a fast open/close/reopen can start a
    /// second scan before the first one's background `Task.detached` (which
    /// is NOT cancelled by the first `.task` being torn down) has finished.
    /// Without serialization, whichever scan happens to *finish* last wins
    /// and persists — even if it started first and read a now-stale
    /// `layout.json`, silently reverting whatever the other scan just wrote
    /// (e.g. a newly-installed app it discovered). Chaining through
    /// `scanQueueTail` makes each call's read-modify-write wait for the
    /// previous one's write to land first, so writes land in call order.
    func bootstrapScan() async {
        let previous = scanQueueTail
        let task = Task { [weak self] in
            _ = await previous?.value
            await self?.performBootstrapScan()
        }
        scanQueueTail = task
        await task.value
    }

    private func performBootstrapScan() async {
        let preferences = (try? preferencesStore.load()) ?? .default
        self.preferences = preferences
        showSystemApplications = preferences.showSystemApplications
        showHiddenInSearch = preferences.showHiddenInSearch
        let urls = preferences.scanDirectories.map { path in
            URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
        }
        // Start from the saved layout so user folders and positions persist.
        layoutStore = LayoutStore(layout: layoutPersistence.load())
        // Sync geometry so 2×2 occupancy uses the configured rows/cols, and
        // push any resulting overflow forward onto later pages.
        //
        // This used to fall through to a *global* `repaginate(force: true)`
        // whenever any folder was enlarged, to fix up stale page capacity
        // from before enlarged folders counted as 4 cells. `updateGrid` (via
        // `enforcePageCapacity`) already accounts for 2×2 occupancy and pages
        // correctly now, so that global repack is no longer needed — and it
        // was actively harmful: bootstrapScan runs on every overlay open, so
        // any user with an enlarged folder had their entire layout flattened
        // and repacked (apps pulled forward from later pages into earlier
        // ones) every single time they opened the launchpad, not just when
        // they intentionally changed rows/columns. Global repacking should
        // only ever happen from an explicit "整理桌面" (tidyGrid) action.
        layoutStore.updateGrid(columns: gridColumns, rows: gridRows)
        let scanner = self.scanner
        let result = await Task.detached(priority: .userInitiated) {
            scanner.scanAll(directories: urls)
        }.value
        DiagLog.write("bootstrapScan: scanned \(urls.map(\.path)) -> \(result.records.count) app(s), \(result.directoryFolders.count) directory-folder(s)")
        applyScanResult(result)
        persistLayout()
    }

    /// Re-reads preferences and applies a grid capacity change using per-page
    /// enforcement (overflow pushes forward; gaps are never filled by pulling
    /// items from later pages). Called when rows/columns change in Settings.
    func applyGridSettingsChange() {
        let newPrefs = (try? preferencesStore.load()) ?? .default
        preferences = newPrefs
        let cols = gridColumns
        let rows = gridRows
        guard layoutStore.layout.grid.columns != cols
            || layoutStore.layout.grid.rows != rows
            || layoutStore.layout.effectivePageCapacity != cols * rows
        else { return }
        layoutStore.updateGrid(columns: cols, rows: rows)
        persistLayout()
    }

    /// Handles dropping one item onto another in the grid. Dropping an app onto
    /// another app creates a folder containing both; dropping an app onto an
    /// existing folder adds it to that folder.
    func handleDrop(sourceID: String, onto target: LaunchpadDisplayItem) {
        // Only plain apps can be dragged for now (not directory/user folders).
        guard !Self.isFolderID(sourceID), sourceID != target.id else { return }

        // If the source was floating (extracted from a folder) it may not be on
        // any page yet — park it next to the target first so createFolder can
        // find a location.
        let onGrid = layoutStore.layout.pages.flatMap({ $0 }).contains(where: {
            if case .app(let id) = $0 { return id == sourceID }; return false
        })
        if !onGrid {
            var targetPage = currentPage
            var targetIndex = 0
            outer: for (pi, page) in layoutStore.layout.pages.enumerated() {
                for (ii, item) in page.enumerated() {
                    switch item {
                    case .app(let id) where id == target.id:
                        targetPage = pi; targetIndex = ii; break outer
                    case .folder(let id) where id == target.id:
                        targetPage = pi; targetIndex = ii; break outer
                    default:
                        break
                    }
                }
            }
            layoutStore.insertApp(appID: sourceID, toPage: targetPage, atIndex: targetIndex)
        }

        switch target.kind {
        case .app:
            let name = defaultFolderName()
            _ = layoutStore.createFolder(name: name, appIDs: [sourceID, target.id], now: Date())
        case .folder(let folder):
            layoutStore.addAppToFolder(appID: sourceID, folderID: folder.id)
        }
        // Do NOT repaginate / compact here — merging into a folder must leave
        // empty slots on the current page (Launchpad behaviour). Gaps are only
        // filled by "整理桌面" or when dragging an app *out* onto a page that
        // still has room.
        persistLayout()
    }

    func renameFolder(id: String, name: String) {
        layoutStore.renameFolder(id: id, name: name)
        persistLayout()
    }

    func reorderInFolder(folderID: String, appID: String, toIndex: Int) {
        layoutStore.reorderFolderItem(folderID: folderID, appID: appID, toIndex: toIndex)
        persistLayout()
    }

    func refreshOpenFolder() {
        guard let folder = openFolder, case .folder(let f) = folder.kind else { return }
        guard let updated = layoutStore.layout.folders.first(where: { $0.id == f.id }) else { return }
        let recordsByID = appIndex.records
        let members = updated.items
            .compactMap { recordsByID[$0] }
            .filter { !layoutStore.layout.hiddenAppIDs.contains($0.id) && !$0.isMissing }
        openFolder = LaunchpadDisplayItem(id: updated.id, title: updated.name, kind: .folder(updated), members: members)
    }

    /// Moves an app's bundle to the system Trash (recoverable) and, once that
    /// succeeds, removes it from the grid and folders and persists the layout.
    func moveToTrash(_ itemID: String) async {
        guard let record = appIndex.records[itemID] else { return }
        let success = await trasher.moveToTrash(path: record.path)
        guard success else { return }
        layoutStore.removeAppEverywhere(record.id)
        persistLayout()
    }

    /// Compacts all pages forward, filling gaps left by apps moved into
    /// folders or trashed, then persists. Triggered by "整理桌面".
    func tidyGrid() {
        layoutStore.compactPages()
        persistLayout()
    }

    func enlargeFolder(id: String) {
        layoutStore.enlargeFolder(id: id)
        // 2×2 occupancy can force a 5th visual row even when cell sum ≤
        // capacity — `updateGrid` (via `enforcePageCapacity`) already
        // accounts for that and only pushes overflow forward onto later
        // pages. A global `repaginate` here would additionally pull apps
        // forward from later pages into this one, which is reserved for an
        // explicit "整理桌面" (tidyGrid) action, not an implicit side effect
        // of enlarging a folder.
        layoutStore.updateGrid(columns: gridColumns, rows: gridRows)
        persistLayout()
    }

    func shrinkFolder(id: String) {
        layoutStore.shrinkFolder(id: id)
        layoutStore.updateGrid(columns: gridColumns, rows: gridRows)
        persistLayout()
    }

    func hideApp(id: String) {
        layoutStore.hideApp(id: id)
        persistLayout()
    }

    func unhideApp(id: String) {
        layoutStore.unhideApp(id: id)
        persistLayout()
    }

    /// Moves an app **or folder** to a new grid slot (reorder / insert only).
    /// Folders never merge with anything — they only change position.
    func moveAppInGrid(sourceID: String, targetPage: Int, targetIndex: Int) {
        layoutStore.moveItem(id: sourceID, toPage: targetPage, index: targetIndex)
        // Only push overflow forward if this page now exceeds capacity —
        // never pull items from later pages to fill holes.
        layoutStore.enforcePageCapacity()
        persistLayout()
    }

    /// Mid-drag live reorder: moves the item without persisting.
    /// Called on every cell-boundary crossing during drag.
    func liveReorder(draggedID: String, toIndex: Int, page: Int) {
        layoutStore.moveItem(id: draggedID, toPage: page, index: toIndex)
    }

    /// Mid-drag live reorder within a folder: moves the member without persisting.
    func liveReorderInFolder(folderID: String, appID: String, toIndex: Int) {
        layoutStore.reorderFolderItem(folderID: folderID, appID: appID, toIndex: toIndex)
        refreshOpenFolder()
    }

    /// Original position before live reorder began (for rollback on cancel).
    private var preReorderPage: [LaunchpadItem] = []
    private var preReorderDragID: String?

    func beginLiveReorder(draggedID: String, page: Int) {
        guard preReorderDragID == nil else { return }
        preReorderDragID = draggedID
        if layoutStore.layout.pages.indices.contains(page) {
            preReorderPage = layoutStore.layout.pages[page]
        }
    }

    func cancelLiveReorder(page: Int) {
        guard preReorderDragID != nil else { return }
        layoutStore.restorePage(preReorderPage, at: page)
        preReorderDragID = nil
        preReorderPage = []
    }

    func endLiveReorder() {
        preReorderDragID = nil
        preReorderPage = []
        // Live reorder may temporarily overflow a page (extra row during drag
        // preview / cross-page insert). On finalize, push overflow forward so
        // no page keeps a permanent 5th row or unfilled capacity violation.
        layoutStore.enforcePageCapacity()
        persistLayout()
    }

    /// Removes an app from its folder and places it at an explicit grid slot.
    @discardableResult
    func removeAppFromFolder(appID: String, toPage: Int? = nil, atIndex: Int? = nil) -> Bool {
        let page = toPage ?? max(0, currentPage)
        let pageItems = layoutStore.layout.pages.indices.contains(page)
            ? layoutStore.layout.pages[page].count
            : 0
        let dissolved = layoutStore.removeAppFromFolder(
            appID: appID,
            toPage: page,
            atIndex: atIndex ?? pageItems
        )
        persistLayout()
        return dissolved
    }

    /// Mid-drag: pull the app out of the open folder, close the popup, and
    /// keep a floating ghost under the pointer. Does **not** place on the grid yet
    /// (first `updateFloatingDrag` inserts it for live gap + merge preview).
    func beginFloatingDragOut(appID: String, at point: CGPoint) {
        guard let record = appIndex.records[appID] else { return }
        DiagLog.write("beginFloatingDragOut appID=\(appID) — closing folder")
        _ = layoutStore.extractAppFromFolder(appID)
        // Instant close (drag continues on the grid) — skip zoom-back.
        finishClosingFolder()
        floatingDragApp = record
        floatingDragItemID = appID
        floatingDragPoint = point
        editDragID = appID
        mergeTargetID = nil
        gridDragItem = nil
        persistLayout()
    }

    /// Hand off a **grid** drag (app or folder) to AppKit floating tracking after
    /// edge page-flip. Keeps the item on the grid; SwiftUI DragGesture is abandoned
    /// so the ghost does not freeze at the screen edge.
    func beginFloatingGridDrag(itemID: String, at point: CGPoint) {
        DiagLog.write("beginFloatingGridDrag itemID=\(itemID) — edge page handoff")
        floatingDragItemID = itemID
        floatingDragApp = appIndex.records[itemID] // nil for folders
        floatingDragPoint = point
        editDragID = itemID
        mergeTargetID = nil
        gridDragItem = nil
        // Stay on grid; first updateFloatingDrag drives live gap on the new page.
    }

    /// While AppKit floating ghost moves: park the item on the grid under the
    /// pointer (live gap / 让位) and, for apps, update folder-create merge sensing.
    func updateFloatingDrag(at point: CGPoint) {
        guard let itemID = floatingDragItemID else { return }
        floatingDragPoint = point
        editDragID = itemID

        let page = currentPage
        beginLiveReorder(draggedID: itemID, page: page)

        let index = insertIndexByPoint(point: point, page: page, excluding: itemID)
        if isItemOnGrid(itemID) {
            if layoutIndex(of: itemID, on: page) != index {
                liveReorder(draggedID: itemID, toIndex: index, page: page)
            }
        } else if !Self.isFolderID(itemID) {
            // Extracted app not yet on grid — insert under pointer.
            layoutStore.insertApp(appID: itemID, toPage: page, atIndex: index)
        }

        // Folders never merge into other tiles — only reorder.
        if Self.isFolderID(itemID) {
            mergeTargetID = nil
        } else {
            mergeTargetID = mergePreviewID(sourceID: itemID, pointer: point, minRatio: 0.35)
        }
    }

    private func isItemOnGrid(_ itemID: String) -> Bool {
        layoutStore.layout.pages.contains { page in
            page.contains { item in
                switch item {
                case .app(let id): return id == itemID
                case .folder(let id): return id == itemID
                }
            }
        }
    }

    /// Display item for floating ghost title / folder chrome.
    func gridDisplayItem(id: String) -> LaunchpadDisplayItem? {
        visiblePages.flatMap { $0 }.first { $0.id == id }
    }

    /// Best merge target id for folder-create sensing (same geometry as drop).
    func mergePreviewID(sourceID: String, pointer: CGPoint, minRatio: CGFloat = 0.35) -> String? {
        let draggedFrame = DragMergeGeometry.draggedFrame(
            sourceID: sourceID,
            pointer: pointer,
            tileFrames: tileFrames
        )
        var bestID: String?
        var bestRatio: CGFloat = 0
        // Enlarged-folder member icons report their own frames too (for the
        // AppKit first-click recovery); exclude them here so dragging near a
        // folder with visible members doesn't preview-merge with one of its
        // apps instead of the folder itself.
        for info in tileFrames where info.id != sourceID && !info.isFolderMember {
            let ratio = DragMergeGeometry.overlapRatio(dragged: draggedFrame, target: info.frame)
            if ratio > bestRatio {
                bestRatio = ratio
                bestID = info.id
            }
        }
        guard bestRatio > minRatio else { return nil }
        return bestID
    }

    /// Finalize a floating drag-out / grid drag.
    ///
    /// Rules:
    /// - **Folder source**: never merges; always reorder/insert only.
    /// - **App source**: merge only when overlap with target is **> 50%**.
    /// - Otherwise insert using cell occupancy + drag translation (accurate
    ///   even when an enlarged 2×2 folder is on the page).
    func resolveDrop(
        sourceID: String,
        at point: CGPoint,
        translation: CGSize = .zero,
        page: Int,
        sourceIndex: Int? = nil
    ) {
        let sourceIsFolder = Self.isFolderID(sourceID)

        // Pointer-centered frame (not layoutFrame+translation). Live reorder
        // already relocates the source cell; adding translation double-counts
        // vertical motion and merges with the row below the visual ghost.
        let draggedFrame = DragMergeGeometry.draggedFrame(
            sourceID: sourceID,
            pointer: point,
            tileFrames: tileFrames
        )

        // Merge path — apps only, > 50% overlap.
        if !sourceIsFolder,
           let hit = bestOverlap(sourceID: sourceID, draggedFrame: draggedFrame),
           hit.ratio > 0.5 {
            handleDrop(sourceID: sourceID, onto: hit.item)
            endLiveReorder()
            clearFloatingDrag()
            return
        }

        // Live reorder already positioned the item — persist and finish.
        if preReorderDragID == sourceID {
            endLiveReorder()
            clearFloatingDrag()
            return
        }

        // Insert / reorder.
        let onGrid = layoutStore.layout.pages.flatMap({ $0 }).contains { item in
            switch item {
            case .app(let id): return id == sourceID
            case .folder(let id): return id == sourceID
            }
        }

        // Prefer layout-page index of the source (visible index can diverge when
        // hidden/missing apps are filtered from the display list).
        let layoutSrcIndex = layoutIndex(of: sourceID, on: page)

        let index: Int
        if let layoutSrcIndex, onGrid {
            index = insertIndexByCellDelta(
                sourceID: sourceID,
                sourceIndex: layoutSrcIndex,
                translation: translation,
                page: page
            )
        } else {
            index = insertIndexByPoint(point: point, page: page, excluding: sourceID)
        }

        if onGrid {
            moveAppInGrid(sourceID: sourceID, targetPage: page, targetIndex: index)
        } else if !sourceIsFolder {
            layoutStore.insertApp(appID: sourceID, toPage: page, atIndex: index)
            persistLayout()
        }
        clearFloatingDrag()
    }

    func clearFloatingDrag() {
        floatingDragApp = nil
        floatingDragItemID = nil
        floatingDragPoint = .zero
        editDragID = nil
        editDragTranslation = .zero
        mergeTargetID = nil
    }

    private func isAppInNoFolder(_ appID: String) -> Bool {
        !layoutStore.layout.folders.contains { $0.items.contains(appID) }
    }

    /// Best overlapping tile and its overlap ratio (area of intersection /
    /// area of the dragged rect). Caller decides the merge threshold (50%).
    private func bestOverlap(
        sourceID: String,
        draggedFrame: CGRect
    ) -> (item: LaunchpadDisplayItem, ratio: CGFloat)? {
        let draggedArea = max(1, draggedFrame.width * draggedFrame.height)
        var best: (item: LaunchpadDisplayItem, ratio: CGFloat)?
        for info in tileFrames where info.id != sourceID {
            let overlap = draggedFrame.intersection(info.frame)
            let area = max(0, overlap.width * overlap.height)
            let ratio = area / draggedArea
            guard ratio > 0 else { continue }
            guard let item = visiblePages.flatMap({ $0 }).first(where: { $0.id == info.id }) else {
                continue
            }
            if best == nil || ratio > best!.ratio {
                best = (item, ratio)
            }
        }
        return best
    }

    /// Insert index from drag translation using the same 7-column occupancy
    /// map as `LaunchpadGridLayout` (handles enlarged 2×2 folders correctly).
    /// Returned index is valid for `moveItem` (remove-then-insert).
    private func insertIndexByCellDelta(
        sourceID: String,
        sourceIndex: Int,
        translation: CGSize,
        page: Int
    ) -> Int {
        guard layoutStore.layout.pages.indices.contains(page) else { return 0 }
        let pageItems = layoutStore.layout.pages[page]
        guard sourceIndex >= 0, sourceIndex < pageItems.count else {
            return insertIndexByPoint(point: .zero, page: page, excluding: sourceID)
        }

        let positions = cellPositions(for: pageItems)
        guard sourceIndex < positions.count else { return 0 }

        let cellW = GridMetrics.tileWidth + GridMetrics.columnSpacing
        let cellH = GridMetrics.tileHeight + GridMetrics.rowSpacing
        let colDelta = Int((translation.width / cellW).rounded())
        let rowDelta = Int((translation.height / cellH).rounded())

        let (srcCol, srcRow) = positions[sourceIndex]
        let targetCol = max(0, min(GridMetrics.columns - 1, srcCol + colDelta))
        let targetRow = max(0, srcRow + rowDelta)

        // Among remaining items (source removed), insert before the first whose
        // top-left cell is at/after (targetCol, targetRow) in reading order.
        var rank = 0
        for (i, _) in pageItems.enumerated() where i != sourceIndex {
            let (c, r) = positions[i]
            if r > targetRow || (r == targetRow && c >= targetCol) {
                return rank
            }
            rank += 1
        }
        return rank // append
    }

    /// Floating drag (out of folder): insert by pointer among remaining tiles.
    ///
    /// Row selection uses the band that **contains** the pointer (not nearest
    /// midY — that preferred the row above when the pointer was in the upper
    /// half of the target row). Within the row, insert by X only.
    private func insertIndexByPoint(point: CGPoint, page: Int, excluding sourceID: String?) -> Int {
        let pageItems = visiblePages.indices.contains(page) ? visiblePages[page] : []
        var ordered: [(rank: Int, rect: CGRect)] = []
        for item in pageItems {
            if item.id == sourceID { continue }
            guard let info = tileFrames.first(where: { $0.id == item.id }) else { continue }
            ordered.append((ordered.count, info.frame))
        }
        guard !ordered.isEmpty else { return 0 }

        // Cluster into visual rows by similar top edge.
        let rowTol = max(24.0, GridMetrics.tileHeight * 0.45)
        var rows: [[(rank: Int, rect: CGRect)]] = []
        for entry in ordered {
            if var last = rows.last, let sample = last.first,
               abs(sample.rect.minY - entry.rect.minY) < rowTol {
                last.append(entry)
                rows[rows.count - 1] = last
            } else {
                rows.append([entry])
            }
        }

        // 1) Prefer the row whose vertical span contains the pointer.
        // 2) Else the first row whose maxY is below the pointer (pointer in gap
        //    above that row → use that row).
        // 3) Else nearest midY.
        var bestRow: Int?
        for (ri, row) in rows.enumerated() {
            let minY = row.map(\.rect.minY).min() ?? 0
            let maxY = row.map(\.rect.maxY).max() ?? 0
            if point.y >= minY && point.y <= maxY {
                bestRow = ri
                break
            }
        }
        if bestRow == nil {
            for (ri, row) in rows.enumerated() {
                let minY = row.map(\.rect.minY).min() ?? 0
                if point.y < minY {
                    bestRow = ri
                    break
                }
            }
        }
        if bestRow == nil {
            var bestDist = CGFloat.greatestFiniteMagnitude
            var ri = rows.count - 1
            for (i, row) in rows.enumerated() {
                let midY = row.map(\.rect.midY).reduce(0, +) / CGFloat(max(1, row.count))
                let d = abs(point.y - midY)
                if d < bestDist {
                    bestDist = d
                    ri = i
                }
            }
            bestRow = ri
        }

        let row = rows[bestRow!].sorted { $0.rect.midX < $1.rect.midX }
        for cell in row {
            if point.x < cell.rect.midX {
                return cell.rank
            }
        }
        if let last = row.last {
            return last.rank + 1
        }
        return ordered.count
    }

    private func layoutIndex(of sourceID: String, on page: Int) -> Int? {
        guard layoutStore.layout.pages.indices.contains(page) else { return nil }
        for (i, item) in layoutStore.layout.pages[page].enumerated() {
            switch item {
            case .app(let id) where id == sourceID: return i
            case .folder(let id) where id == sourceID: return i
            default: break
            }
        }
        return nil
    }

    /// Top-left grid cell for each item on a page (matches LaunchpadGridLayout).
    private func cellPositions(for pageItems: [LaunchpadItem]) -> [(col: Int, row: Int)] {
        var occupied = Set<String>()
        var col = 0
        var row = 0
        var result: [(Int, Int)] = []
        let columns = GridMetrics.columns

        func key(_ c: Int, _ r: Int) -> String { "\(c),\(r)" }

        for item in pageItems {
            while occupied.contains(key(col, row)) {
                col += 1
                if col >= columns { col = 0; row += 1 }
            }
            let isEnlarged: Bool = {
                if case .folder(let id) = item {
                    return layoutStore.layout.enlargedFolderIDs.contains(id)
                }
                return false
            }()

            result.append((col, row))
            if isEnlarged, col + 1 < columns {
                occupied.insert(key(col, row))
                occupied.insert(key(col + 1, row))
                occupied.insert(key(col, row + 1))
                occupied.insert(key(col + 1, row + 1))
                col += 2
            } else {
                occupied.insert(key(col, row))
                col += 1
            }
            if col >= columns { col = 0; row += 1 }
        }
        return result
    }

    func appRecord(id: String) -> AppRecord? {
        appIndex.records[id]
    }

    /// All currently-hidden app records, for the settings management list.
    var hiddenApps: [AppRecord] {
        layoutStore.layout.hiddenAppIDs.compactMap { appIndex.records[$0] }
    }

    func isFolderEnlarged(_ id: String) -> Bool {
        layoutStore.isEnlarged(id)
    }

    var enlargedFolderIDs: Set<String> {
        layoutStore.layout.enlargedFolderIDs
    }

    private func defaultFolderName() -> String {
        let base = "新文件夹"
        let existing = Set(layoutStore.layout.folders.map(\.name))
        guard existing.contains(base) else { return base }
        var suffix = 2
        while existing.contains("\(base) \(suffix)") { suffix += 1 }
        return "\(base) \(suffix)"
    }

    private static func isFolderID(_ id: String) -> Bool {
        id.hasPrefix("folder:") || id.hasPrefix("dir:")
    }

    private static func isSystemApp(_ record: AppRecord) -> Bool {
        record.source == .systemApplications || record.bundleID?.hasPrefix("com.apple.") == true
    }

    func persistCurrentLayout() {
        persistLayout()
    }

    private func persistLayout() {
        layoutPersistence.save(layoutStore.layout)
    }
}
