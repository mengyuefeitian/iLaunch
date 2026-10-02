import Foundation

struct LaunchpadLayout: Codable, Equatable {
    struct Grid: Codable, Equatable {
        var columns: Int
        var rows: Int
        var iconSize: Double
    }

    var pages: [[LaunchpadItem]]
    var folders: [LaunchpadFolder]
    var hiddenAppIDs: Set<String>
    var grid: Grid
    /// Items per page, recorded from the screen-adaptive grid the last time
    /// the layout was saved. nil in legacy files, which paginated at a fixed
    /// columns x rows (7 x 5 = 35).
    var pageCapacity: Int?
    /// Folder ids that the user has enlarged to a 2×2 tile (3×3 internal grid).
    var enlargedFolderIDs: Set<String> = []
    /// Managed folders (Apple / directory-backed) the user dissolved; syncs must
    /// not re-create them.
    var dissolvedFolderIDs: Set<String> = []

    var effectivePageCapacity: Int {
        pageCapacity ?? max(1, grid.columns * grid.rows)
    }

    static let empty = LaunchpadLayout(
        pages: [[]],
        folders: [],
        hiddenAppIDs: [],
        grid: .init(columns: 7, rows: 5, iconSize: 72),
        pageCapacity: nil,
        enlargedFolderIDs: []
    )

    private enum CodingKeys: String, CodingKey {
        case pages, folders, hiddenAppIDs, grid, pageCapacity, enlargedFolderIDs, dissolvedFolderIDs
    }

    init(pages: [[LaunchpadItem]], folders: [LaunchpadFolder], hiddenAppIDs: Set<String>, grid: Grid, pageCapacity: Int? = nil, enlargedFolderIDs: Set<String> = []) {
        self.pages = pages
        self.folders = folders
        self.hiddenAppIDs = hiddenAppIDs
        self.grid = grid
        self.pageCapacity = pageCapacity
        self.enlargedFolderIDs = enlargedFolderIDs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pages = try c.decode([[LaunchpadItem]].self, forKey: .pages)
        folders = try c.decode([LaunchpadFolder].self, forKey: .folders)
        hiddenAppIDs = try c.decode(Set<String>.self, forKey: .hiddenAppIDs)
        grid = try c.decode(Grid.self, forKey: .grid)
        pageCapacity = try c.decodeIfPresent(Int.self, forKey: .pageCapacity)
        enlargedFolderIDs = try c.decodeIfPresent(Set<String>.self, forKey: .enlargedFolderIDs) ?? []
        dissolvedFolderIDs = try c.decodeIfPresent(Set<String>.self, forKey: .dissolvedFolderIDs) ?? []
    }
}
