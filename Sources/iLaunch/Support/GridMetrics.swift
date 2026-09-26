import CoreGraphics

/// Shared layout constants for the Launchpad grid, plus the screen-adaptive
/// row count. Tiles keep their full design size (no visual compression);
/// instead the number of rows per page follows the screen's point height —
/// 4 rows on a 1080p layout, more on taller 4K/5K layouts, like the native
/// Launchpad which fills larger displays with a bigger grid rather than
/// stretching icons.
enum GridMetrics {
    static let columns = 7
    static let tileWidth: CGFloat = 132
    static let tileHeight: CGFloat = 150
    static let iconSize: CGFloat = 104
    static let columnSpacing: CGFloat = 24
    static let rowSpacing: CGFloat = 34

    /// Vertical space taken by everything outside the grid: search field top
    /// padding (60) + field (~38) + stack spacing (32) + dots spacing (18) +
    /// page dots (~25) + bottom margin (40).
    static let chromeHeight: CGFloat = 213

    /// Never drop below this many rows, even on very short screens; the view
    /// shrinks tiles slightly instead as a last resort.
    static let minimumRows = 4

    /// Full-size rows that fit a screen of the given point height.
    /// 1080 → 4 rows, 1440 → 6 rows, 2160 → 10 rows.
    static func rows(forScreenHeight height: CGFloat) -> Int {
        let available = height - chromeHeight
        let fitted = Int(((available + rowSpacing) / (tileHeight + rowSpacing)).rounded(.down))
        return max(minimumRows, fitted)
    }

    static func pageCapacity(rows: Int) -> Int {
        columns * rows
    }

    /// Returns the user-configured row count (clamped to valid range 4–6).
    static func effectiveRows(preference: Int, screenHeight: CGFloat) -> Int {
        if preference >= 4 && preference <= 6 {
            return preference
        }
        return 4
    }

    /// Returns the user-configured column count (clamped to valid range).
    static func effectiveColumns(preference: Int) -> Int {
        min(max(preference, 6), 10)
    }

    /// Computes cell dimensions for a fixed rows×cols grid within the given area.
    /// `availableWidth` should already exclude side margins (e.g. screen − 150×2).
    /// Resulting `width` fills that band evenly — do not cap it or apps clump.
    static func cellSize(rows: Int, columns: Int, availableWidth: CGFloat, availableHeight: CGFloat) -> (width: CGFloat, height: CGFloat) {
        let cellWidth = (availableWidth - CGFloat(columns - 1) * columnSpacing) / CGFloat(columns)
        let cellHeight = (availableHeight - CGFloat(rows - 1) * rowSpacing) / CGFloat(rows)
        return (max(cellWidth, 60), max(cellHeight, 60))
    }

    /// Vertical space the Dock physically occupies at the bottom of the
    /// screen. The overlay window always spans the full screen frame, so
    /// when the Dock stays visible on top of it (`coverDock == false`) the
    /// grid must stop above that strip or its bottom row renders underneath
    /// the Dock. `visibleFrame`'s origin already excludes that reserved
    /// strip from `frame`'s origin, so their difference is the Dock height.
    /// When `coverDock == true` the overlay renders above the Dock's window
    /// level instead, so no reservation is needed.
    static func dockReservedHeight(coverDock: Bool, screenFrameMinY: CGFloat, visibleFrameMinY: CGFloat) -> CGFloat {
        guard !coverDock else { return 0 }
        return max(0, visibleFrameMinY - screenFrameMinY)
    }

    /// Exact 2×2 span of two adjacent app cells (uses the *live* tile metrics).
    static func enlargedSpan(
        tileWidth: CGFloat,
        tileHeight: CGFloat,
        columnSpacing: CGFloat = columnSpacing,
        rowSpacing: CGFloat = rowSpacing
    ) -> CGSize {
        CGSize(
            width: tileWidth * 2 + columnSpacing,
            height: tileHeight * 2 + rowSpacing
        )
    }
}
