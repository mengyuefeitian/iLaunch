import CoreGraphics

/// Shared layout constants and helpers for the Launchpad grid.
enum GridMetrics {
    static let columns = 7
    static let tileWidth: CGFloat = 132
    static let tileHeight: CGFloat = 150
    static let iconSize: CGFloat = 104
    static let columnSpacing: CGFloat = 24
    static let rowSpacing: CGFloat = 34

    static func pageCapacity(rows: Int) -> Int {
        columns * rows
    }

    /// Returns the user-configured row count (clamped to valid range 4–6).
    static func effectiveRows(preference: Int) -> Int {
        if preference >= 4 && preference <= 6 {
            return preference
        }
        return 4
    }

    /// Returns the user-configured column count (clamped to valid range).
    static func effectiveColumns(preference: Int) -> Int {
        min(max(preference, 6), 10)
    }

    /// Rows × columns for the screen's orientation. On a portrait display the
    /// (clamped) landscape rows and columns are swapped, so page capacity and
    /// reading order stay identical and only the wrap width changes.
    static func effectiveGrid(
        rowsPreference: Int,
        columnsPreference: Int,
        isPortrait: Bool
    ) -> (rows: Int, columns: Int) {
        let rows = effectiveRows(preference: rowsPreference)
        let columns = effectiveColumns(preference: columnsPreference)
        return isPortrait ? (rows: columns, columns: rows) : (rows: rows, columns: columns)
    }

    /// A screen is portrait only when strictly taller than wide.
    static func isPortrait(screenSize: CGSize) -> Bool {
        screenSize.height > screenSize.width
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
