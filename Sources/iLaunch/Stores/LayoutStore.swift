import Foundation

struct LayoutStore {
    private(set) var layout: LaunchpadLayout

    init(layout: LaunchpadLayout = .empty) {
        self.layout = layout
    }

    /// Re-chunks all page items preserving order so each page packs into at
    /// most `capacity` cells **and** at most `grid.rows` visual rows under the
    /// same 2×2 occupancy rules as `LaunchpadGridLayout`.
    ///
    /// Cell-count alone is not enough: several enlarged folders can sum to
    /// ≤28 cells yet still need a 5th row when laid out on a 7×4 grid.
    mutating func repaginate(capacity: Int, force: Bool = false) {
        guard capacity > 0 else { return }
        let columns = max(1, layout.grid.columns)
        let maxRows = max(1, capacity / columns)
        guard force
            || layout.effectivePageCapacity != capacity
            || layout.grid.rows != maxRows
        else { return }

        layout.pageCapacity = capacity
        layout.grid.rows = maxRows
        let items = layout.pages.flatMap { $0 }
        layout.pages = packItemsByOccupancy(
            items,
            columns: columns,
            maxRows: maxRows,
            capacity: capacity
        )
    }

    /// Sets geometry used by occupancy packing, then pushes overflow forward.
    mutating func updateGrid(columns: Int, rows: Int) {
        let columns = max(1, columns)
        let rows = max(1, rows)
        layout.grid.columns = columns
        layout.grid.rows = rows
        layout.pageCapacity = columns * rows
        enforcePageCapacity()
    }

    /// Updates the page capacity without global compaction. Only pushes
    /// overflow forward when capacity shrinks; never pulls items backward
    /// from later pages when capacity grows.
    mutating func updateCapacity(_ capacity: Int) {
        guard capacity > 0 else { return }
        layout.pageCapacity = capacity
        let columns = max(1, layout.grid.columns)
        layout.grid.rows = max(1, capacity / columns)
        enforcePageCapacity()
    }

    mutating func appendNewApps(_ appIDs: [String]) {
        var existing = Set(layout.pages.flatMap { page in
            page.compactMap { item -> String? in
                if case .app(let id) = item { return id }
                return nil
            }
        }).union(layout.folders.flatMap(\.items))

        let capacity = max(1, layout.effectivePageCapacity)
        for appID in appIDs where !existing.contains(appID) && !layout.hiddenAppIDs.contains(appID) {
            if layout.pages.isEmpty { layout.pages = [[]] }
            let lastPage = layout.pages.count - 1
            let currentCells = layout.pages[lastPage].reduce(0) { $0 + cellCost($1) }
            if currentCells >= capacity {
                layout.pages.append([])
            }
            layout.pages[layout.pages.count - 1].append(.app(appID))
            existing.insert(appID)
        }
    }

    /// Upserts directory-backed folders (e.g. /Applications/Python 3.13) into the layout.
    /// Member apps are removed from page grids so they only appear inside the folder,
    /// and the folder itself is placed once if not already present.
    mutating func syncDirectoryFolders(_ folders: [DirectoryFolder], now: Date = Date()) {
        for directoryFolder in folders where !layout.dissolvedFolderIDs.contains(directoryFolder.id) {
            if let index = layout.folders.firstIndex(where: { $0.id == directoryFolder.id }) {
                layout.folders[index].items = directoryFolder.appIDs
                layout.folders[index].updatedAt = now
            } else {
                layout.folders.append(LaunchpadFolder(
                    id: directoryFolder.id,
                    name: directoryFolder.name,
                    items: directoryFolder.appIDs,
                    createdAt: now,
                    updatedAt: now
                ))
            }
            for appID in directoryFolder.appIDs {
                removeItem(id: "app:\(appID)")
            }
            if !containsFolderItem(directoryFolder.id) {
                if layout.pages.isEmpty { layout.pages = [[]] }
                layout.pages[layout.pages.count - 1].append(.folder(directoryFolder.id))
            }
        }
    }

    /// Stable id of the managed folder that holds Apple's own apps.
    static let appleFolderID = "folder:apple"

    /// Keeps Apple's own apps (bundle id prefix `com.apple.`) together in one
    /// managed folder named "Apple".
    ///
    /// Two phases:
    /// - First sighting (no `folder:apple` yet): collect every Apple app that is
    ///   not hidden and not already inside another folder — including apps already
    ///   placed on grid pages — so an existing user's scattered Apple apps get
    ///   unified into the folder. Requires at least two such apps.
    /// - Afterwards (`folder:apple` exists): additive only. Only brand-new Apple
    ///   apps that appear nowhere yet (not on a page, not in any folder) join, so
    ///   apps a user dragged out of the folder or moved elsewhere stay put. The
    ///   folder is found by its stable id, so a renamed folder still works.
    mutating func syncAppleFolder(appleAppIDs: [String], name: String = "Apple", now: Date = Date()) {
        // User dissolved the Apple folder: leave its apps on the grid.
        guard !layout.dissolvedFolderIDs.contains(Self.appleFolderID) else { return }
        let onPages = Set(layout.pages.flatMap { page in
            page.compactMap { item -> String? in
                if case .app(let id) = item { return id }
                return nil
            }
        })
        let inFolders = Set(layout.folders.flatMap(\.items))

        if let index = layout.folders.firstIndex(where: { $0.id == Self.appleFolderID }) {
            // Additive only: collect apps that appear nowhere yet.
            let newApps = appleAppIDs.filter {
                !onPages.contains($0) && !inFolders.contains($0) && !layout.hiddenAppIDs.contains($0)
            }
            guard !newApps.isEmpty else { return }
            layout.folders[index].items.append(contentsOf: newApps)
            layout.folders[index].updatedAt = now
            return
        }

        // First sighting: unify all eligible Apple apps, even ones already on
        // the grid, but leave apps the user already grouped in another folder.
        let candidates = appleAppIDs.filter {
            !inFolders.contains($0) && !layout.hiddenAppIDs.contains($0)
        }
        guard candidates.count >= 2 else { return }
        let folder = LaunchpadFolder(
            id: Self.appleFolderID,
            name: name,
            items: candidates,
            createdAt: now,
            updatedAt: now
        )
        for appID in candidates {
            removeItem(id: "app:\(appID)")
        }
        layout.folders.append(folder)
        if layout.pages.isEmpty { layout.pages = [[]] }
        if !containsFolderItem(folder.id) {
            layout.pages[0].insert(.folder(folder.id), at: 0)
        }
        // Removing the Apple apps leaves gaps across the pages; flow the
        // remaining apps forward into dense pages so the grid is not left
        // paginated half-empty.
        compactPages()
    }

    mutating func addAppToFolder(appID: String, folderID: String, now: Date = Date()) {
        guard let index = layout.folders.firstIndex(where: { $0.id == folderID }) else { return }
        guard !layout.folders[index].items.contains(appID) else { return }
        layout.folders[index].items.append(appID)
        layout.folders[index].updatedAt = now
        removeItem(id: "app:\(appID)")
        removeEmptyTrailingPages()
    }

    /// Dissolves a folder of any size: members return to the page grid in order
    /// at the folder's former slot; overflow spills onto following pages.
    /// Managed (Apple / directory) folders are remembered so syncs don't re-create them.
    mutating func dissolveFolder(id folderID: String) {
        guard let folderIndex = layout.folders.firstIndex(where: { $0.id == folderID }) else { return }
        let members = layout.folders[folderIndex].items

        var folderPage = 0
        var folderSlot = 0
        var found = false
        outer: for (pi, page) in layout.pages.enumerated() {
            for (ii, item) in page.enumerated() {
                if case .folder(let id) = item, id == folderID {
                    folderPage = pi
                    folderSlot = ii
                    found = true
                    break outer
                }
            }
        }
        if layout.pages.isEmpty { layout.pages = [[]] }

        if found {
            layout.pages[folderPage].remove(at: folderSlot)
        }
        for member in members { removeItem(id: "app:\(member)") }
        let slot = min(folderSlot, layout.pages[folderPage].count)
        layout.pages[folderPage].insert(contentsOf: members.map { LaunchpadItem.app($0) }, at: slot)

        layout.enlargedFolderIDs.remove(folderID)
        layout.folders.remove(at: folderIndex)
        if folderID == Self.appleFolderID || folderID.hasPrefix("dir:") {
            layout.dissolvedFolderIDs.insert(folderID)
        }
        reflowOverflow(from: folderPage)
        removeEmptyTrailingPages()
    }

    /// Pulls an app out of its folder **without** placing it on the grid.
    /// Used mid-drag so the floating ghost can follow the pointer; the caller
    /// later places it via `insertApp` / `createFolder` / `addAppToFolder`.
    /// Returns whether the folder was dissolved (and the leftover app id, if any,
    /// which is placed at the folder's former slot).
    @discardableResult
    mutating func extractAppFromFolder(_ appID: String) -> (dissolved: Bool, leftoverAppID: String?) {
        guard let folderIndex = layout.folders.firstIndex(where: { $0.items.contains(appID) }) else {
            return (false, nil)
        }
        let folderID = layout.folders[folderIndex].id

        var folderPage = 0
        var folderSlot = 0
        outer: for (pi, page) in layout.pages.enumerated() {
            for (ii, item) in page.enumerated() {
                if case .folder(let id) = item, id == folderID {
                    folderPage = pi
                    folderSlot = ii
                    break outer
                }
            }
        }

        layout.folders[folderIndex].items.removeAll { $0 == appID }
        let remaining = layout.folders[folderIndex].items

        if remaining.count <= 1 {
            layout.pages[folderPage].removeAll { item in
                if case .folder(let id) = item { return id == folderID }
                return false
            }
            layout.enlargedFolderIDs.remove(folderID)
            layout.folders.remove(at: folderIndex)
            var leftover: String? = nil
            if let lastApp = remaining.first {
                let slot = min(folderSlot, layout.pages[folderPage].count)
                layout.pages[folderPage].insert(.app(lastApp), at: slot)
                leftover = lastApp
            }
            reflowOverflow(from: folderPage)
            return (true, leftover)
        }
        return (false, nil)
    }

    /// Inserts an app onto a page at `index`, pushing later items forward and
    /// spilling overflow to subsequent pages. Enforces cell capacity so a
    /// page never visually grows past the design row count (e.g. 4×7).
    mutating func insertApp(appID: String, toPage page: Int, atIndex index: Int) {
        // Ensure the app is not already on any page (avoid duplicates).
        removeItem(id: "app:\(appID)")
        if layout.pages.isEmpty { layout.pages = [[]] }
        let targetPage = min(max(0, page), layout.pages.count - 1)
        let slot = min(max(0, index), layout.pages[targetPage].count)
        layout.pages[targetPage].insert(.app(appID), at: slot)
        reflowOverflow(from: targetPage)
    }

    /// Removes an app from whatever folder it's in and places it back on the
    /// grid so it stays **visible**.
    ///
    /// Placement priority:
    /// 1. Explicit `toPage` / `atIndex` (drop position under the pointer)
    /// 2. Otherwise the folder tile's page/slot
    ///
    /// Returns `true` when the folder was dissolved.
    @discardableResult
    mutating func removeAppFromFolder(
        appID: String,
        toPage: Int? = nil,
        atIndex: Int? = nil
    ) -> Bool {
        // Remember folder location before extract for fallback placement.
        var folderPage = 0
        var folderSlot = 0
        if let folder = layout.folders.first(where: { $0.items.contains(appID) }) {
            outer: for (pi, page) in layout.pages.enumerated() {
                for (ii, item) in page.enumerated() {
                    if case .folder(let id) = item, id == folder.id {
                        folderPage = pi
                        folderSlot = ii
                        break outer
                    }
                }
            }
        }

        let (dissolved, _) = extractAppFromFolder(appID)

        let alreadyOnGrid = layout.pages.contains { page in
            page.contains { if case .app(let id) = $0 { return id == appID }; return false }
        }
        guard !alreadyOnGrid else { return dissolved }

        if layout.pages.isEmpty { layout.pages = [[]] }
        let targetPage: Int = {
            if let toPage { return min(max(0, toPage), max(0, layout.pages.count - 1)) }
            return min(folderPage, max(0, layout.pages.count - 1))
        }()
        let slot: Int = {
            if let atIndex { return min(max(0, atIndex), layout.pages[targetPage].count) }
            // Default: beside where the folder is / was.
            if targetPage == folderPage { return min(folderSlot, layout.pages[targetPage].count) }
            return layout.pages[targetPage].count
        }()
        layout.pages[targetPage].insert(.app(appID), at: slot)
        reflowOverflow(from: targetPage)
        return dissolved
    }

    /// When a page exceeds cell capacity **or** packs past `grid.rows` under
    /// 2×2 occupancy, move trailing items onto the next page (front-insert so
    /// order is preserved). Cascades forward without pulling items backward.
    private mutating func reflowOverflow(from startPage: Int) {
        let columns = max(1, layout.grid.columns)
        let maxRows = max(1, layout.grid.rows)
        let capacity = max(1, layout.effectivePageCapacity)
        var page = max(0, startPage)
        while page < layout.pages.count {
            while pageFits(
                layout.pages[page],
                columns: columns,
                maxRows: maxRows,
                capacity: capacity
            ) == false,
                let last = layout.pages[page].last
            {
                layout.pages[page].removeLast()
                if page + 1 >= layout.pages.count {
                    layout.pages.append([])
                }
                layout.pages[page + 1].insert(last, at: 0)
            }
            page += 1
        }
        removeEmptyTrailingPages()
    }

    mutating func renameFolder(id: String, name: String, now: Date = Date()) {
        guard let index = layout.folders.firstIndex(where: { $0.id == id }) else { return }
        layout.folders[index].name = name
        layout.folders[index].updatedAt = now
    }

    mutating func reorderFolderItem(folderID: String, appID: String, toIndex: Int) {
        guard let fi = layout.folders.firstIndex(where: { $0.id == folderID }) else { return }
        layout.folders[fi].items.removeAll { $0 == appID }
        let clamped = min(max(0, toIndex), layout.folders[fi].items.count)
        layout.folders[fi].items.insert(appID, at: clamped)
        layout.folders[fi].updatedAt = Date()
    }

    /// Removes page items and folder members whose app id is no longer present
    /// in the latest scan, so uninstalled apps don't leave blank cells or dead
    /// references behind.
    mutating func pruneApps(notIn validIDs: Set<String>) {
        for pageIndex in layout.pages.indices {
            layout.pages[pageIndex].removeAll { item in
                if case .app(let id) = item { return !validIDs.contains(id) }
                return false
            }
        }
        for folderIndex in layout.folders.indices {
            layout.folders[folderIndex].items.removeAll { !validIDs.contains($0) }
        }
        removeEmptyTrailingPages()
    }

    mutating func moveItem(id: String, toPage page: Int, index: Int) {
        let targetItem = item(from: id)
        // Remove by item equality — the old id-string comparison failed because
        // LaunchpadItem.id prepends "app:" / "folder:" while the caller passes
        // the raw display-item id, so the old item was never removed and every
        // drag created a duplicate.
        for pageIndex in layout.pages.indices {
            layout.pages[pageIndex].removeAll { $0 == targetItem }
        }
        while layout.pages.count <= page {
            layout.pages.append([])
        }
        let boundedIndex = min(max(0, index), layout.pages[page].count)
        layout.pages[page].insert(targetItem, at: boundedIndex)
        removeEmptyTrailingPages()
    }

    /// Restores a page's items to a previously-snapshotted state (drag cancellation rollback).
    mutating func restorePage(_ items: [LaunchpadItem], at page: Int) {
        guard layout.pages.indices.contains(page) else { return }
        layout.pages[page] = items
    }

    mutating func createFolder(name: String, appIDs: [String], now: Date) -> LaunchpadFolder {
        let folder = LaunchpadFolder(
            id: "folder:\(UUID().uuidString)",
            name: name,
            items: appIDs,
            createdAt: now,
            updatedAt: now
        )
        let firstLocation = firstLocationOfApp(ids: appIDs) ?? (0, 0)
        for appID in appIDs {
            removeItem(id: "app:\(appID)")
        }
        layout.folders.append(folder)
        while layout.pages.count <= firstLocation.page {
            layout.pages.append([])
        }
        let index = min(firstLocation.index, layout.pages[firstLocation.page].count)
        layout.pages[firstLocation.page].insert(.folder(folder.id), at: index)
        removeEmptyTrailingPages()
        return folder
    }

    /// Removes an app from every page and from all folder member lists after
    /// it has been moved to the Trash, so its tile disappears immediately.
    mutating func removeAppEverywhere(_ appID: String) {
        removeItem(id: "app:\(appID)")
        for folderIndex in layout.folders.indices {
            layout.folders[folderIndex].items.removeAll { $0 == appID }
        }
        removeEmptyTrailingPages()
    }

    mutating func hideApp(id: String) {
        layout.hiddenAppIDs.insert(id)
        removeItem(id: "app:\(id)")
    }

    mutating func unhideApp(id: String) {
        layout.hiddenAppIDs.remove(id)
    }

    mutating func resetLayout(keepingHiddenApps: Bool) {
        let hidden = keepingHiddenApps ? layout.hiddenAppIDs : []
        let grid = layout.grid
        layout = LaunchpadLayout(
            pages: [[]],
            folders: [],
            hiddenAppIDs: hidden,
            grid: grid,
            enlargedFolderIDs: []
        )
    }

    private mutating func removeItem(id: String) {
        for pageIndex in layout.pages.indices {
            layout.pages[pageIndex].removeAll { $0.id == id }
        }
    }

    private func containsFolderItem(_ folderID: String) -> Bool {
        layout.pages.contains { page in
            page.contains { item in
                if case .folder(let id) = item { return id == folderID }
                return false
            }
        }
    }

    private func item(from id: String) -> LaunchpadItem {
        if id.hasPrefix("folder:") || id.hasPrefix("dir:") {
            return .folder(id)
        }
        return .app(id.replacingOccurrences(of: "app:", with: ""))
    }

    private func firstLocationOfApp(ids: [String]) -> (page: Int, index: Int)? {
        for pageIndex in layout.pages.indices {
            for itemIndex in layout.pages[pageIndex].indices {
                if case .app(let id) = layout.pages[pageIndex][itemIndex], ids.contains(id) {
                    return (pageIndex, itemIndex)
                }
            }
        }
        return nil
    }

    private mutating func removeEmptyTrailingPages() {
        while layout.pages.count > 1 && layout.pages.last?.isEmpty == true {
            layout.pages.removeLast()
        }
    }

    /// Enlarged folders occupy 2×2 = 4 grid cells; everything else is 1 cell.
    private func cellCost(_ item: LaunchpadItem) -> Int {
        if case .folder(let id) = item, layout.enlargedFolderIDs.contains(id) {
            return 4
        }
        return 1
    }

    /// Flattens every page (preserving order) and re-chunks with 2×2 occupancy
    /// so no page needs more than `grid.rows` visual rows (or cell capacity).
    mutating func compactPages() {
        let columns = max(1, layout.grid.columns)
        let maxRows = max(1, layout.grid.rows)
        let capacity = max(1, layout.effectivePageCapacity)
        let items = layout.pages.flatMap { $0 }
        guard !items.isEmpty else {
            layout.pages = [[]]
            return
        }
        layout.pages = packItemsByOccupancy(
            items,
            columns: columns,
            maxRows: maxRows,
            capacity: capacity
        )
    }

    // MARK: - 2×2 occupancy packing (mirrors LaunchpadGridLayout)

    /// Cell-sum and occupancy row limits must both pass.
    func pageFits(
        _ items: [LaunchpadItem],
        columns: Int,
        maxRows: Int,
        capacity: Int
    ) -> Bool {
        let cells = items.reduce(0) { $0 + cellCost($1) }
        if cells > capacity { return false }
        return rowsUsedByOccupancy(items, columns: columns) <= maxRows
    }

    /// Rows needed by left-to-right / top-to-bottom packing with enlarged 2×2.
    ///
    /// Each item is placed in the **first free cell that fits** (scan from
    /// top-left). Cursor-only packing left permanent holes when a 2×2 skipped
    /// past the end of a row and later 1×1s never back-filled.
    func rowsUsedByOccupancy(_ items: [LaunchpadItem], columns: Int) -> Int {
        let columns = max(1, columns)
        var occupied = Set<CellKey>()

        for item in items {
            if isEnlargedItem(item) {
                if let place = firstFreeEnlargedCell(columns: columns, occupied: occupied) {
                    occupied.insert(CellKey(col: place.col, row: place.row))
                    occupied.insert(CellKey(col: place.col + 1, row: place.row))
                    occupied.insert(CellKey(col: place.col, row: place.row + 1))
                    occupied.insert(CellKey(col: place.col + 1, row: place.row + 1))
                } else if let place = firstFreeCell(columns: columns, occupied: occupied) {
                    // Fallback 1×1 (same as layout)
                    occupied.insert(CellKey(col: place.col, row: place.row))
                }
            } else if let place = firstFreeCell(columns: columns, occupied: occupied) {
                occupied.insert(CellKey(col: place.col, row: place.row))
            }
        }

        return (occupied.map(\.row).max() ?? -1) + 1
    }

    /// First free 1×1 cell in reading order.
    private func firstFreeCell(columns: Int, occupied: Set<CellKey>, maxRows: Int = 200) -> (col: Int, row: Int)? {
        for row in 0..<maxRows {
            for col in 0..<columns {
                if !occupied.contains(CellKey(col: col, row: row)) {
                    return (col, row)
                }
            }
        }
        return nil
    }

    /// First free 2×2 top-left in reading order.
    private func firstFreeEnlargedCell(columns: Int, occupied: Set<CellKey>, maxRows: Int = 200) -> (col: Int, row: Int)? {
        guard columns >= 2 else { return nil }
        for row in 0..<maxRows {
            for col in 0..<(columns - 1) {
                if canPlaceEnlarged(col: col, row: row, columns: columns, occupied: occupied) {
                    return (col, row)
                }
            }
        }
        return nil
    }

    /// Pack items into pages that each respect cell capacity and ≤ `maxRows`.
    private func packItemsByOccupancy(
        _ items: [LaunchpadItem],
        columns: Int,
        maxRows: Int,
        capacity: Int
    ) -> [[LaunchpadItem]] {
        let columns = max(1, columns)
        let maxRows = max(1, maxRows)
        let capacity = max(1, capacity)
        var pages: [[LaunchpadItem]] = []
        var current: [LaunchpadItem] = []
        for item in items {
            var trial = current
            trial.append(item)
            if !current.isEmpty
                && pageFits(trial, columns: columns, maxRows: maxRows, capacity: capacity) == false
            {
                pages.append(current)
                current = [item]
            } else {
                current = trial
            }
        }
        if !current.isEmpty { pages.append(current) }
        return pages.isEmpty ? [[]] : pages
    }

    private func isEnlargedItem(_ item: LaunchpadItem) -> Bool {
        if case .folder(let id) = item {
            return layout.enlargedFolderIDs.contains(id)
        }
        return false
    }

    private func canPlaceEnlarged(
        col: Int,
        row: Int,
        columns: Int,
        occupied: Set<CellKey>
    ) -> Bool {
        guard col + 1 < columns else { return false }
        return !occupied.contains(CellKey(col: col, row: row))
            && !occupied.contains(CellKey(col: col + 1, row: row))
            && !occupied.contains(CellKey(col: col, row: row + 1))
            && !occupied.contains(CellKey(col: col + 1, row: row + 1))
    }

    private struct CellKey: Hashable {
        let col: Int
        let row: Int
    }

    /// Marks a folder as enlarged (displayed as a 2×2 tile with 3×3 internal grid).
    /// Caller must repaginate — enlarging costs +3 cells and can overflow a page.
    mutating func enlargeFolder(id: String) {
        layout.enlargedFolderIDs.insert(id)
    }

    /// Reverts a folder back to its normal 1×1 tile size.
    mutating func shrinkFolder(id: String) {
        layout.enlargedFolderIDs.remove(id)
    }

    /// Public overflow reflow so ViewModel can enforce capacity after enlarge.
    mutating func enforcePageCapacity() {
        if layout.pages.isEmpty { return }
        reflowOverflow(from: 0)
        // Also walk every page in case earlier pages were under capacity after
        // a shrink; reflowOverflow only pushes forward, which is enough to
        // stop 5-row pages.
        for i in layout.pages.indices {
            reflowOverflow(from: i)
        }
    }

    /// Whether a folder is currently in enlarged mode.
    func isEnlarged(_ id: String) -> Bool {
        layout.enlargedFolderIDs.contains(id)
    }

    /// Dissolves folders that have lost all (or all but one) members.
    /// Zero-member folders are removed entirely; one-member folders are
    /// replaced by the remaining app at the folder's grid position.
    /// Called during bootstrap to clean up historical leftovers and after
    /// any operation that removes apps from folders.
    mutating func dissolveEmptyFolders() {
        var changed = false
        // Iterate in reverse so removals don't shift indices.
        for folderIndex in layout.folders.indices.reversed() {
            let folder = layout.folders[folderIndex]
            // Skip directory-backed folders (managed by the scanner).
            if folder.id.hasPrefix("dir:") { continue }
            guard folder.items.count <= 1 else { continue }

            // Locate the folder tile on the grid.
            var folderPage: Int? = nil
            var folderSlot = 0
            outer: for (pi, page) in layout.pages.enumerated() {
                for (ii, item) in page.enumerated() {
                    if case .folder(let id) = item, id == folder.id {
                        folderPage = pi
                        folderSlot = ii
                        break outer
                    }
                }
            }

            // Remove the folder tile from the page.
            if let fp = folderPage {
                layout.pages[fp].removeAll { item in
                    if case .folder(let id) = item { return id == folder.id }
                    return false
                }
                // Place the last remaining app (if any) at the folder's old slot.
                if let lastApp = folder.items.first {
                    let slot = min(folderSlot, layout.pages[fp].count)
                    layout.pages[fp].insert(.app(lastApp), at: slot)
                }
            }

            layout.enlargedFolderIDs.remove(folder.id)
            layout.folders.remove(at: folderIndex)
            changed = true
        }
        if changed {
            removeEmptyTrailingPages()
        }
    }
}
