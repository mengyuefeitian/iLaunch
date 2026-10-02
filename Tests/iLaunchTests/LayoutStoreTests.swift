import Foundation
import Testing
@testable import iLaunch

@Test func layoutRoundTripsThroughJSON() throws {
    let app = AppRecord(
        id: "bundle:com.example.Editor",
        bundleID: "com.example.Editor",
        name: "Editor",
        localizedName: "Editor",
        path: "/Applications/Editor.app",
        iconCacheKey: "bundle:com.example.Editor",
        version: "1.0",
        source: .userApplications,
        isHidden: false,
        isMissing: false,
        lastSeenAt: Date(timeIntervalSince1970: 10),
        lastLaunchedAt: nil
    )
    let layout = LaunchpadLayout(
        pages: [[.app(app.id)]],
        folders: [],
        hiddenAppIDs: [],
        grid: .init(columns: 7, rows: 5, iconSize: 72)
    )
    let data = try JSONEncoder.iLaunch.encode(layout)
    let decoded = try JSONDecoder.iLaunch.decode(LaunchpadLayout.self, from: data)
    #expect(decoded == layout)
}

@Test func appendNewAppsDoesNotDuplicateExistingItems() {
    var store = LayoutStore(layout: .init(
        pages: [[.app("a")]],
        folders: [],
        hiddenAppIDs: [],
        grid: .init(columns: 2, rows: 1, iconSize: 72)
    ))
    store.appendNewApps(["a", "b", "c"])
    #expect(store.layout.pages == [[.app("a"), .app("b")], [.app("c")]])
}

@Test func createFolderRemovesAppsFromPagesAndAddsFolder() {
    var store = LayoutStore(layout: .init(
        pages: [[.app("a"), .app("b"), .app("c")]],
        folders: [],
        hiddenAppIDs: [],
        grid: .init(columns: 7, rows: 5, iconSize: 72)
    ))
    let folder = store.createFolder(
        name: "Work",
        appIDs: ["a", "b"],
        now: Date(timeIntervalSince1970: 1)
    )
    #expect(folder.name == "Work")
    #expect(folder.items == ["a", "b"])
    #expect(store.layout.pages[0] == [.folder(folder.id), .app("c")])
}

@Test func removeAppEverywhereClearsPagesAndFolderMembers() {
    var store = LayoutStore(layout: .init(
        pages: [[.app("a"), .app("b")], [.app("c")]],
        folders: [
            LaunchpadFolder(
                id: "folder:1",
                name: "Work",
                items: ["a", "c"],
                createdAt: Date(timeIntervalSince1970: 1),
                updatedAt: Date(timeIntervalSince1970: 1)
            )
        ],
        hiddenAppIDs: [],
        grid: .init(columns: 7, rows: 5, iconSize: 72)
    ))
    store.removeAppEverywhere("a")
    #expect(store.layout.pages == [[.app("b")], [.app("c")]])
    #expect(store.layout.folders[0].items == ["c"])
}

@Test func hideAndUnhideApp() {
    var store = LayoutStore(layout: .init(
        pages: [[.app("a")]],
        folders: [],
        hiddenAppIDs: [],
        grid: .init(columns: 7, rows: 5, iconSize: 72)
    ))
    store.hideApp(id: "a")
    #expect(store.layout.hiddenAppIDs.contains("a"))
    #expect(store.layout.pages == [[]])
    store.unhideApp(id: "a")
    #expect(!store.layout.hiddenAppIDs.contains("a"))
}

@Test func resetLayoutCanKeepHiddenApps() {
    var store = LayoutStore(layout: .init(
        pages: [[.app("a")]],
        folders: [],
        hiddenAppIDs: ["secret"],
        grid: .init(columns: 7, rows: 5, iconSize: 72)
    ))
    store.resetLayout(keepingHiddenApps: true)
    #expect(store.layout.pages == [[]])
    #expect(store.layout.hiddenAppIDs == ["secret"])
}

@Test func addAppToFolderMovesAppOutOfGrid() {
    var store = LayoutStore(layout: .init(
        pages: [[.app("a"), .app("b")]],
        folders: [LaunchpadFolder(id: "folder:1", name: "F", items: ["a"], createdAt: Date(), updatedAt: Date())],
        hiddenAppIDs: [],
        grid: .init(columns: 7, rows: 5, iconSize: 72)
    ))
    store.addAppToFolder(appID: "b", folderID: "folder:1")
    #expect(store.layout.folders[0].items == ["a", "b"])
    #expect(store.layout.pages[0] == [.app("a")])
}

@Test func renameFolderUpdatesName() {
    var store = LayoutStore(layout: .init(
        pages: [[.folder("folder:1")]],
        folders: [LaunchpadFolder(id: "folder:1", name: "Old", items: [], createdAt: Date(), updatedAt: Date())],
        hiddenAppIDs: [],
        grid: .init(columns: 7, rows: 5, iconSize: 72)
    ))
    store.renameFolder(id: "folder:1", name: "New")
    #expect(store.layout.folders[0].name == "New")
}

@Test func pruneAppsRemovesStaleItems() {
    var store = LayoutStore(layout: .init(
        pages: [[.app("a"), .app("gone"), .folder("folder:1")]],
        folders: [],
        hiddenAppIDs: [],
        grid: .init(columns: 7, rows: 5, iconSize: 72)
    ))
    store.pruneApps(notIn: ["a"])
    #expect(store.layout.pages[0] == [.app("a"), .folder("folder:1")])
}

@Test func syncDirectoryFoldersGroupsMemberApps() {
    var store = LayoutStore(layout: .init(
        pages: [[.app("path:/Applications/Python 3.13/IDLE.app"), .app("other")]],
        folders: [],
        hiddenAppIDs: [],
        grid: .init(columns: 7, rows: 5, iconSize: 72)
    ))
    let folder = DirectoryFolder(
        id: "dir:/Applications/Python 3.13",
        name: "Python 3.13",
        path: "/Applications/Python 3.13",
        appIDs: ["path:/Applications/Python 3.13/IDLE.app"]
    )
    store.syncDirectoryFolders([folder])

    // The member app is no longer a top-level grid item; the folder is.
    #expect(store.layout.pages[0].contains(.folder("dir:/Applications/Python 3.13")))
    #expect(!store.layout.pages[0].contains(.app("path:/Applications/Python 3.13/IDLE.app")))
    #expect(store.layout.folders.map(\.id) == ["dir:/Applications/Python 3.13"])
}

@Test func repaginateRechunksLegacyPagesPreservingOrder() {
    // Legacy layout: 45 items across 35-item pages, no recorded capacity.
    let items = (0..<44).map { LaunchpadItem.app("app\($0)") }
    var all = items
    all.insert(.folder("folder:1"), at: 10)
    var store = LayoutStore(layout: .init(
        pages: [Array(all.prefix(35)), Array(all.suffix(10))],
        folders: [],
        hiddenAppIDs: [],
        grid: .init(columns: 7, rows: 5, iconSize: 72)
    ))

    store.repaginate(capacity: 28)

    #expect(store.layout.pages.count == 2)
    #expect(store.layout.pages[0].count == 28)
    #expect(store.layout.pages[1].count == 17)
    #expect(store.layout.pages.flatMap { $0 } == all)
    #expect(store.layout.pageCapacity == 28)
}

@Test func repaginateConsolidatesWhenCapacityGrows() {
    let items = (0..<84).map { LaunchpadItem.app("app\($0)") }
    var store = LayoutStore(layout: .init(
        pages: [Array(items[0..<28]), Array(items[28..<56]), Array(items[56..<84])],
        folders: [],
        hiddenAppIDs: [],
        grid: .init(columns: 7, rows: 6, iconSize: 72),
        pageCapacity: 28
    ))

    store.repaginate(capacity: 42)

    #expect(store.layout.pages.map(\.count) == [42, 42])
    #expect(store.layout.pages.flatMap { $0 } == items)
    #expect(store.layout.pageCapacity == 42)
}

@Test func repaginateIsNoOpWhenCapacityMatches() {
    let pages: [[LaunchpadItem]] = [[.app("a"), .app("b")], [.app("c")]]
    var store = LayoutStore(layout: .init(
        pages: pages,
        folders: [],
        hiddenAppIDs: [],
        grid: .init(columns: 7, rows: 4, iconSize: 72),
        pageCapacity: 28
    ))

    store.repaginate(capacity: 28)

    #expect(store.layout.pages == pages)
}

/// Several enlarged folders can sum to ≤28 cells yet still need a 5th row when
/// packed on a 7×4 grid. Occupancy packing must spill to the next page.
/// When a 2×2 enlarged folder skips past the end of a row, later 1×1 apps must
/// back-fill the hole instead of leaving a permanent empty cell mid-grid.
@Test func occupancyPackingFillsHolesLeftByEnlargedSkip() {
    // 7 columns: six 1×1 apps then an enlarged folder that cannot fit at col 6,
    // so it jumps to the next row — col 6 of row 0 must still be filled by a
    // subsequent app (not left empty while row 1 grows).
    let folder = LaunchpadFolder(
        id: "folder:big",
        name: "Big",
        items: ["m0", "m1"],
        createdAt: Date(timeIntervalSince1970: 1),
        updatedAt: Date(timeIntervalSince1970: 1)
    )
    // 6 apps + enlarged + 2 more apps
    let items: [LaunchpadItem] = (0..<6).map { .app("a\($0)") }
        + [.folder(folder.id)]
        + [.app("tail0"), .app("tail1")]
    var store = LayoutStore(layout: .init(
        pages: [items],
        folders: [folder],
        hiddenAppIDs: [],
        grid: .init(columns: 7, rows: 4, iconSize: 72),
        pageCapacity: 28,
        enlargedFolderIDs: [folder.id]
    ))

    // With hole-filling: row0 has 6 apps + 1 filled by tail → 7 cells used on
    // row0; enlarged sits on row1 (2 rows). Without hole-fill, row0 ends with
    // an empty col6 while tails sit after the enlarged block → taller layout.
    let rows = store.rowsUsedByOccupancy(items, columns: 7)
    #expect(rows <= 3)

    store.enforcePageCapacity()
    #expect(store.pageFits(store.layout.pages[0], columns: 7, maxRows: 4, capacity: 28))
}

/// moveItem during drag may exceed capacity; enforcePageCapacity must push
/// trailing items to the next page (final drop path).
@Test func enforcePageCapacityPushesOverflowAfterMoveItem() {
    let page0 = (0..<28).map { LaunchpadItem.app("app\($0)") }
    var store = LayoutStore(layout: .init(
        pages: [page0, [.app("extra")]],
        folders: [],
        hiddenAppIDs: [],
        grid: .init(columns: 7, rows: 4, iconSize: 72),
        pageCapacity: 28
    ))

    store.moveItem(id: "extra", toPage: 0, index: 28)
    #expect(store.layout.pages[0].count == 29)

    store.enforcePageCapacity()
    #expect(store.layout.pages[0].count == 28)
    #expect(store.layout.pages.flatMap { $0 }.contains(.app("extra")))
    #expect(store.pageFits(store.layout.pages[0], columns: 7, maxRows: 4, capacity: 28))
}

@Test func multipleEnlargedFoldersDoNotExceedConfiguredRows() {
    // 3 enlarged folders (2×2 each) + 20 apps — cell sum = 3*4+20 = 32, but
    // even a cell-valid 28-item mix can pack tall; use many enlarged + fillers.
    let folders: [LaunchpadFolder] = (0..<4).map { i in
        LaunchpadFolder(
            id: "folder:e\(i)",
            name: "E\(i)",
            items: ["a\(i)0", "a\(i)1"],
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
    }
    var page: [LaunchpadItem] = folders.map { .folder($0.id) }
    page.append(contentsOf: (0..<16).map { .app("app\($0)") })
    var store = LayoutStore(layout: .init(
        pages: [page],
        folders: folders,
        hiddenAppIDs: [],
        grid: .init(columns: 7, rows: 4, iconSize: 72),
        pageCapacity: 28,
        enlargedFolderIDs: Set(folders.map(\.id))
    ))

    #expect(store.rowsUsedByOccupancy(page, columns: 7) > 4)

    store.repaginate(capacity: 28, force: true)

    for page in store.layout.pages {
        #expect(store.rowsUsedByOccupancy(page, columns: 7) <= 4)
    }
    // Nothing lost.
    #expect(store.layout.pages.flatMap { $0 }.count == page.count)
}

@Test func appendNewAppsUsesRecordedPageCapacity() {
    // Grid config says 7x5, but the recorded capacity (from a 4-row screen)
    // is 28 — new apps must start a new page at 28, not 35.
    var store = LayoutStore(layout: .init(
        pages: [(0..<28).map { LaunchpadItem.app("app\($0)") }],
        folders: [],
        hiddenAppIDs: [],
        grid: .init(columns: 7, rows: 5, iconSize: 72),
        pageCapacity: 28
    ))

    store.appendNewApps(["new"])

    #expect(store.layout.pages.count == 2)
    #expect(store.layout.pages[1] == [.app("new")])
}

@Test func syncAppleFolderCreatesFolderForAppleApps() {
    var store = LayoutStore(layout: .init(
        pages: [[.app("a")]],
        folders: [],
        hiddenAppIDs: [],
        grid: .init(columns: 7, rows: 5, iconSize: 72)
    ))
    store.syncAppleFolder(appleAppIDs: ["com.apple.Mail", "com.apple.Safari"])

    guard let folder = store.layout.folders.first(where: { $0.id == "folder:apple" }) else {
        Issue.record("expected folder:apple to be created")
        return
    }
    #expect(folder.name == "Apple")
    #expect(folder.items.sorted() == ["com.apple.Mail", "com.apple.Safari"])
    #expect(store.layout.pages.flatMap { $0 }.contains(.folder("folder:apple")))
}

@Test func syncAppleFolderAddsOnlyNewApps() {
    // Mail is on a page (user dragged it out -> settled), Safari is already a
    // member, Notes is brand new (nowhere yet).
    var store = LayoutStore(layout: .init(
        pages: [[.app("com.apple.Mail")]],
        folders: [LaunchpadFolder(
            id: "folder:apple", name: "Apple",
            items: ["com.apple.Safari"], createdAt: Date(), updatedAt: Date()
        )],
        hiddenAppIDs: [],
        grid: .init(columns: 7, rows: 5, iconSize: 72)
    ))
    store.syncAppleFolder(appleAppIDs: ["com.apple.Mail", "com.apple.Safari", "com.apple.Notes"])

    let folder = store.layout.folders.first(where: { $0.id == "folder:apple" })!
    #expect(folder.items.contains("com.apple.Notes"))
    #expect(!folder.items.contains("com.apple.Mail"))
    // Mail stays on the page; it is not yanked back into the folder.
    #expect(store.layout.pages[0].contains(.app("com.apple.Mail")))
}

@Test func syncAppleFolderSkipsWhenFewerThanTwo() {
    var store = LayoutStore(layout: .init(
        pages: [[.app("a")]],
        folders: [],
        hiddenAppIDs: [],
        grid: .init(columns: 7, rows: 5, iconSize: 72)
    ))
    store.syncAppleFolder(appleAppIDs: ["com.apple.Mail"])
    #expect(store.layout.folders.isEmpty)
}

@Test func syncAppleFolderKeepsWorkingAfterRename() {
    var store = LayoutStore(layout: .init(
        pages: [[.app("a")]],
        folders: [LaunchpadFolder(
            id: "folder:apple", name: "苹果",
            items: ["com.apple.Safari"], createdAt: Date(), updatedAt: Date()
        )],
        hiddenAppIDs: [],
        grid: .init(columns: 7, rows: 5, iconSize: 72)
    ))
    store.syncAppleFolder(appleAppIDs: ["com.apple.Safari", "com.apple.Notes"])

    let folder = store.layout.folders.first(where: { $0.id == "folder:apple" })!
    #expect(folder.name == "苹果")
    #expect(folder.items.contains("com.apple.Notes"))
}

@Test func syncAppleFolderExcludesHiddenApps() {
    var store = LayoutStore(layout: .init(
        pages: [[.app("a")]],
        folders: [],
        hiddenAppIDs: ["com.apple.Mail"],
        grid: .init(columns: 7, rows: 5, iconSize: 72)
    ))
    // Mail is hidden; only Safari and Notes are eligible, so the folder is
    // still created (two eligible apps) but must not contain the hidden Mail.
    store.syncAppleFolder(appleAppIDs: ["com.apple.Mail", "com.apple.Safari", "com.apple.Notes"])

    guard let folder = store.layout.folders.first(where: { $0.id == "folder:apple" }) else {
        Issue.record("expected folder:apple to be created")
        return
    }
    #expect(!folder.items.contains("com.apple.Mail"))
    #expect(folder.items.sorted() == ["com.apple.Notes", "com.apple.Safari"])
}

@Test func syncAppleFolderCollectsScatteredAppsOnFirstCreation() {
    // Realistic migration: an existing user already has Apple apps scattered
    // across the grid. The first run must gather them into the folder.
    var store = LayoutStore(layout: .init(
        pages: [[.app("com.apple.Mail"), .app("x")], [.app("com.apple.Safari")]],
        folders: [],
        hiddenAppIDs: [],
        grid: .init(columns: 7, rows: 5, iconSize: 72)
    ))
    store.syncAppleFolder(appleAppIDs: ["com.apple.Mail", "com.apple.Safari"])

    guard let folder = store.layout.folders.first(where: { $0.id == "folder:apple" }) else {
        Issue.record("expected folder:apple to be created from scattered apps")
        return
    }
    #expect(folder.items.sorted() == ["com.apple.Mail", "com.apple.Safari"])
    // The scattered Apple apps are removed from the pages; non-Apple "x" stays.
    let pageApps = store.layout.pages.flatMap { $0 }.compactMap { item -> String? in
        if case .app(let id) = item { return id }
        return nil
    }
    #expect(pageApps == ["x"])
    #expect(store.layout.pages.flatMap { $0 }.contains(.folder("folder:apple")))
}

@Test func syncAppleFolderCompactsRemainingAppsIntoDensePages() {
    // Apple apps are scattered across several underfilled pages. After they are
    // gathered into the folder, the remaining apps must flow forward into dense
    // pages so the user is not left flipping through pages full of gaps.
    var store = LayoutStore(layout: .init(
        pages: [
            [.app("com.apple.Mail"), .app("a")],
            [.app("b")],
            [.app("com.apple.Safari"), .app("c")],
        ],
        folders: [],
        hiddenAppIDs: [],
        grid: .init(columns: 7, rows: 5, iconSize: 72),
        pageCapacity: 2
    ))
    store.syncAppleFolder(appleAppIDs: ["com.apple.Mail", "com.apple.Safari"])

    // Apple folder + a, b, c = 4 items at capacity 2 -> exactly 2 dense pages.
    let items = store.layout.pages.flatMap { $0 }
    #expect(items.count == 4)
    #expect(store.layout.pages.count == 2)
    #expect(store.layout.pages.allSatisfy { $0.count == 2 })
    #expect(items.contains(.folder("folder:apple")))
}

@Test func syncAppleFolderDoesNotDuplicateFolderTile() {
    // Regression: an inconsistent state (a folder:apple tile on the grid but no
    // folder definition) must not lead to a second folder:apple tile being
    // inserted on the next consolidation — that left a stray empty slot.
    var store = LayoutStore(layout: .init(
        pages: [[.folder("folder:apple"), .app("a")]],
        folders: [],
        hiddenAppIDs: [],
        grid: .init(columns: 7, rows: 5, iconSize: 72)
    ))
    store.syncAppleFolder(appleAppIDs: ["com.apple.Mail", "com.apple.Safari"])

    let tileCount = store.layout.pages
        .flatMap { $0 }
        .filter { $0 == .folder("folder:apple") }
        .count
    #expect(tileCount == 1)
}

// MARK: - removeAppFromFolder (drag-out)

@Test func removeAppFromFolderInsertsBesideFolderAndKeepsVisible() {
    // Dragging an app out of a multi-member folder must put it on the grid
    // (next to the folder), never drop it silently.
    var store = LayoutStore(layout: .init(
        pages: [[.app("x"), .folder("folder:1"), .app("y")]],
        folders: [
            LaunchpadFolder(
                id: "folder:1",
                name: "Work",
                items: ["a", "b", "c"],
                createdAt: Date(timeIntervalSince1970: 1),
                updatedAt: Date(timeIntervalSince1970: 1)
            )
        ],
        hiddenAppIDs: [],
        grid: .init(columns: 7, rows: 5, iconSize: 72),
        pageCapacity: 28
    ))
    let dissolved = store.removeAppFromFolder(appID: "b")
    #expect(dissolved == false)
    #expect(store.layout.folders[0].items == ["a", "c"])
    // Inserted at the folder's slot (index 1), pushing the folder right.
    #expect(store.layout.pages[0].contains(.app("b")))
    #expect(store.layout.pages.flatMap { $0 }.contains(.folder("folder:1")))
}

@Test func removeAppFromFolderInsertsOnRequestedPageNotLastPage() {
    // User is viewing page 0; drag-out must land on page 0 and push siblings,
    // not get appended to the last page. Use a tight capacity so we can also
    // verify overflow pushes forward without merging earlier pages.
    var store = LayoutStore(layout: .init(
        pages: [
            [.folder("folder:1"), .app("x")],
            [.app("p1"), .app("p2")],
            [.app("last")]
        ],
        folders: [
            LaunchpadFolder(
                id: "folder:1",
                name: "Work",
                items: ["a", "b", "c"],
                createdAt: Date(timeIntervalSince1970: 1),
                updatedAt: Date(timeIntervalSince1970: 1)
            )
        ],
        hiddenAppIDs: [],
        grid: .init(columns: 7, rows: 5, iconSize: 72),
        pageCapacity: 4
    ))
    let dissolved = store.removeAppFromFolder(appID: "a", toPage: 0, atIndex: 1)
    #expect(dissolved == false)
    #expect(store.layout.pages[0] == [.folder("folder:1"), .app("a"), .app("x")])
    // Still present on page 0, never only on the last page.
    #expect(store.layout.pages[0].contains(.app("a")))
    #expect(store.layout.folders[0].items == ["b", "c"])
    // Later pages stay separate (not compacted into page 0).
    #expect(store.layout.pages.count >= 2)
    #expect(store.layout.pages[1].contains(.app("p1")) || store.layout.pages[1].contains(.app("p2")))
}

@Test func removeAppFromFolderDissolvePlacesDraggedAppOnGrid() {
    // When the folder dissolves (≤1 remaining), the dragged-out app must
    // still appear on the grid (not vanish).
    var store = LayoutStore(layout: .init(
        pages: [[.app("x"), .folder("folder:1")]],
        folders: [
            LaunchpadFolder(
                id: "folder:1",
                name: "Work",
                items: ["a", "b"],
                createdAt: Date(timeIntervalSince1970: 1),
                updatedAt: Date(timeIntervalSince1970: 1)
            )
        ],
        hiddenAppIDs: [],
        grid: .init(columns: 7, rows: 5, iconSize: 72),
        pageCapacity: 28
    ))
    let dissolved = store.removeAppFromFolder(appID: "a", toPage: 0, atIndex: 1)
    #expect(dissolved == true)
    #expect(store.layout.folders.isEmpty)
    let page0 = store.layout.pages[0]
    #expect(page0.contains(.app("a")))
    #expect(page0.contains(.app("b")))
    #expect(page0.contains(.app("x")))
    #expect(!page0.contains { if case .folder = $0 { return true }; return false })
}

// MARK: - reorderFolderItem

@Test func reorderFolderItemMovesAppToNewIndex() {
    var store = LayoutStore(layout: .init(
        pages: [[.folder("folder:test")]],
        folders: [LaunchpadFolder(
            id: "folder:test",
            name: "Test",
            items: ["a", "b", "c", "d"],
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        )],
        hiddenAppIDs: [],
        grid: .init(columns: 7, rows: 5, iconSize: 72)
    ))

    store.reorderFolderItem(folderID: "folder:test", appID: "d", toIndex: 0)
    #expect(store.layout.folders[0].items == ["d", "a", "b", "c"])

    store.reorderFolderItem(folderID: "folder:test", appID: "a", toIndex: 3)
    #expect(store.layout.folders[0].items == ["d", "b", "c", "a"])
}

@Test func reorderFolderItemClampsOutOfBoundsIndex() {
    var store = LayoutStore(layout: .init(
        pages: [[.folder("folder:test")]],
        folders: [LaunchpadFolder(
            id: "folder:test",
            name: "Test",
            items: ["a", "b"],
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        )],
        hiddenAppIDs: [],
        grid: .init(columns: 7, rows: 5, iconSize: 72)
    ))

    store.reorderFolderItem(folderID: "folder:test", appID: "a", toIndex: 99)
    #expect(store.layout.folders[0].items == ["b", "a"])

    store.reorderFolderItem(folderID: "folder:test", appID: "b", toIndex: -5)
    #expect(store.layout.folders[0].items == ["b", "a"])
}

@Test func reorderFolderItemIgnoresUnknownFolder() {
    var store = LayoutStore(layout: .init(
        pages: [[.folder("folder:test")]],
        folders: [LaunchpadFolder(
            id: "folder:test",
            name: "Test",
            items: ["a", "b"],
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        )],
        hiddenAppIDs: [],
        grid: .init(columns: 7, rows: 5, iconSize: 72)
    ))

    store.reorderFolderItem(folderID: "folder:nonexistent", appID: "a", toIndex: 1)
    #expect(store.layout.folders[0].items == ["a", "b"])
}


// MARK: - dissolveFolder

private func dissolveStore(
    pages: [[LaunchpadItem]],
    folders: [LaunchpadFolder],
    columns: Int = 4,
    rows: Int = 1,
    enlarged: Set<String> = []
) -> LayoutStore {
    LayoutStore(layout: .init(
        pages: pages,
        folders: folders,
        hiddenAppIDs: [],
        grid: .init(columns: columns, rows: rows, iconSize: 72),
        enlargedFolderIDs: enlarged
    ))
}

private func makeFolder(_ id: String, _ items: [String]) -> LaunchpadFolder {
    LaunchpadFolder(id: id, name: id, items: items, createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0))
}

@Test func dissolveFolderPutsMembersBackInOrderAtFolderSlot() {
    var store = dissolveStore(
        pages: [[.app("x"), .folder("f"), .app("y")]],
        folders: [makeFolder("f", ["a", "b"])],
        columns: 6
    )
    store.dissolveFolder(id: "f")
    #expect(store.layout.folders.isEmpty)
    #expect(store.layout.pages == [[.app("x"), .app("a"), .app("b"), .app("y")]])
}

@Test func dissolveFolderSpillsOverflowToNextPage() {
    var store = dissolveStore(
        pages: [[.app("x"), .folder("f"), .app("y"), .app("z")]],
        folders: [makeFolder("f", ["a", "b", "c"])],
        columns: 4
    )
    store.dissolveFolder(id: "f")
    #expect(store.layout.pages == [
        [.app("x"), .app("a"), .app("b"), .app("c")],
        [.app("y"), .app("z")],
    ])
}

@Test func dissolveFolderClearsEnlargedFlag() {
    var store = dissolveStore(
        pages: [[.folder("f")]],
        folders: [makeFolder("f", ["a", "b", "c", "d", "e"])],
        columns: 7,
        enlarged: ["f"]
    )
    store.dissolveFolder(id: "f")
    #expect(store.layout.enlargedFolderIDs.isEmpty)
    #expect(store.layout.pages == [[.app("a"), .app("b"), .app("c"), .app("d"), .app("e")]])
}

@Test func dissolveUnknownFolderIsNoOp() {
    var store = dissolveStore(
        pages: [[.folder("f")]],
        folders: [makeFolder("f", ["a", "b"])]
    )
    let before = store.layout
    store.dissolveFolder(id: "nope")
    #expect(store.layout == before)
}

@Test func dissolvedAppleFolderIsNotRecreatedBySync() {
    var store = dissolveStore(
        pages: [[.folder(LayoutStore.appleFolderID)]],
        folders: [makeFolder(LayoutStore.appleFolderID, ["a", "b"])],
        columns: 6
    )
    store.dissolveFolder(id: LayoutStore.appleFolderID)
    store.syncAppleFolder(appleAppIDs: ["a", "b"])
    #expect(store.layout.folders.isEmpty)
    #expect(store.layout.pages == [[.app("a"), .app("b")]])
}

@Test func dissolvedDirectoryFolderIsNotRecreatedBySync() {
    var store = dissolveStore(
        pages: [[.folder("dir:py")]],
        folders: [makeFolder("dir:py", ["a", "b"])],
        columns: 6
    )
    store.dissolveFolder(id: "dir:py")
    store.syncDirectoryFolders([DirectoryFolder(id: "dir:py", name: "py", path: "/Applications/py", appIDs: ["a", "b"])])
    #expect(store.layout.folders.isEmpty)
    #expect(store.layout.pages == [[.app("a"), .app("b")]])
}
