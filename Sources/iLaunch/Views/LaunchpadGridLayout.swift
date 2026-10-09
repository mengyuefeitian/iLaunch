import SwiftUI

/// Layout value key that marks a subview as enlarged (spanning 2×2 cells).
private struct EnlargedKey: LayoutValueKey {
    static let defaultValue = false
}

extension View {
    func layoutEnlarged(_ enlarged: Bool) -> some View {
        layoutValue(key: EnlargedKey.self, value: enlarged)
    }
}

/// A grid layout that arranges tiles in a fixed column count, allowing
/// enlarged items to span 2 columns × 2 rows. Uses a simple occupancy map
/// to flow items around enlarged tiles.
struct LaunchpadGridLayout: Layout {
    var columns: Int
    var tileWidth: CGFloat = GridMetrics.tileWidth
    var tileHeight: CGFloat = GridMetrics.tileHeight
    var columnSpacing: CGFloat = GridMetrics.columnSpacing
    var rowSpacing: CGFloat = GridMetrics.rowSpacing
    var minRows: Int = 4  // Minimum rows for centering calculation

    struct Cache {
        var positions: [CGPoint] = []
        var sizes: [CGSize] = []
        var totalHeight: CGFloat = 0
    }

    func makeCache(subviews: Subviews) -> Cache {
        computeLayout(subviews: subviews)
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache = computeLayout(subviews: subviews)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let contentWidth = CGFloat(columns) * tileWidth + CGFloat(columns - 1) * columnSpacing
        let minHeight = CGFloat(minRows) * tileHeight + CGFloat(minRows - 1) * rowSpacing
        let height = max(cache.totalHeight, minHeight)
        return CGSize(width: contentWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        for (index, subview) in subviews.enumerated() {
            guard index < cache.positions.count else { break }
            let pos = cache.positions[index]
            let size = cache.sizes[index]
            subview.place(
                at: CGPoint(x: bounds.minX + pos.x, y: bounds.minY + pos.y),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )
        }
    }

    private func computeLayout(subviews: Subviews) -> Cache {
        var occupied = Set<CellKey>()
        var positions: [CGPoint] = []
        var sizes: [CGSize] = []

        // Must match EnlargedFolderTileView / GridMetrics.enlargedSpan exactly
        // so the chrome sits on A-left→B-right and C-top→D-label-bottom.
        let enlarged = GridMetrics.enlargedSpan(
            tileWidth: tileWidth,
            tileHeight: tileHeight,
            columnSpacing: columnSpacing,
            rowSpacing: rowSpacing
        )

        // Place each item in the first free cell that fits (scan from top-left).
        // Cursor-only packing left holes when a 2×2 skipped the end of a row
        // and later 1×1 tiles never back-filled (visible gap mid-grid).
        for subview in subviews {
            let isEnlarged = subview[EnlargedKey.self]

            if isEnlarged, let place = firstFreeEnlargedCell(occupied: occupied) {
                let x = CGFloat(place.col) * (tileWidth + columnSpacing)
                let y = CGFloat(place.row) * (tileHeight + rowSpacing)
                positions.append(CGPoint(x: x, y: y))
                sizes.append(enlarged)
                occupied.insert(CellKey(col: place.col, row: place.row))
                occupied.insert(CellKey(col: place.col + 1, row: place.row))
                occupied.insert(CellKey(col: place.col, row: place.row + 1))
                occupied.insert(CellKey(col: place.col + 1, row: place.row + 1))
            } else if let place = firstFreeCell(occupied: occupied) {
                // 1×1, or enlarged fallback when no 2×2 slot remains.
                let x = CGFloat(place.col) * (tileWidth + columnSpacing)
                let y = CGFloat(place.row) * (tileHeight + rowSpacing)
                positions.append(CGPoint(x: x, y: y))
                sizes.append(CGSize(width: tileWidth, height: tileHeight))
                occupied.insert(CellKey(col: place.col, row: place.row))
            }
        }

        // Compute total height from max row used
        let maxRow = occupied.map(\.row).max() ?? 0
        let totalHeight = CGFloat(maxRow + 1) * tileHeight + CGFloat(maxRow) * rowSpacing

        return Cache(positions: positions, sizes: sizes, totalHeight: totalHeight)
    }

    /// First free 1×1 cell in reading order (fills holes left by 2×2 skips).
    private func firstFreeCell(occupied: Set<CellKey>, maxRows: Int = 200) -> (col: Int, row: Int)? {
        let cols = max(1, columns)
        for row in 0..<maxRows {
            for col in 0..<cols {
                if !occupied.contains(CellKey(col: col, row: row)) {
                    return (col, row)
                }
            }
        }
        return nil
    }

    /// First free 2×2 top-left in reading order.
    private func firstFreeEnlargedCell(occupied: Set<CellKey>, maxRows: Int = 200) -> (col: Int, row: Int)? {
        let cols = max(1, columns)
        guard cols >= 2 else { return nil }
        for row in 0..<maxRows {
            for col in 0..<(cols - 1) {
                if canPlaceEnlarged(col: col, row: row, occupied: occupied) {
                    return (col, row)
                }
            }
        }
        return nil
    }

    private func canPlaceEnlarged(col: Int, row: Int, occupied: Set<CellKey>) -> Bool {
        guard col + 1 < columns else { return false }
        // minRows is the configured page row count — never let 2×2 span past it.
        guard minRows <= 0 || row + 1 < minRows else { return false }
        return !occupied.contains(CellKey(col: col, row: row))
            && !occupied.contains(CellKey(col: col + 1, row: row))
            && !occupied.contains(CellKey(col: col, row: row + 1))
            && !occupied.contains(CellKey(col: col + 1, row: row + 1))
    }
}

private struct CellKey: Hashable {
    let col: Int
    let row: Int
}
