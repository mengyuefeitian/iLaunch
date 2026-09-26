import CoreGraphics
import Testing
@testable import iLaunch

@Test func gridRowsAdaptToScreenHeight() {
    // 1080p point layout: 4 full-size rows, no compression.
    #expect(GridMetrics.rows(forScreenHeight: 1080) == 4)
    // Short laptop screens never drop below 4 rows (tiles shrink slightly
    // instead, as a last resort).
    #expect(GridMetrics.rows(forScreenHeight: 900) == 4)
    // Taller 4K/5K point layouts gain rows instead of stretching icons.
    #expect(GridMetrics.rows(forScreenHeight: 1440) == 6)
    #expect(GridMetrics.rows(forScreenHeight: 2160) == 10)
}

@Test func pageCapacityFollowsRowCount() {
    #expect(GridMetrics.pageCapacity(rows: 4) == 28)
    #expect(GridMetrics.pageCapacity(rows: 6) == 42)
}

/// Side margins 150+150; the middle band is divided evenly — width must grow
/// with available space (capping caused apps to clump).
@Test func cellSizeFillsAvailableWidthEvenly() {
    let sidePadding: CGFloat = 150
    let screenWidth: CGFloat = 1512
    let available = screenWidth - sidePadding * 2
    let columns = 7
    let cell = GridMetrics.cellSize(
        rows: 4,
        columns: columns,
        availableWidth: available,
        availableHeight: 700
    )
    let total = CGFloat(columns) * cell.width
        + CGFloat(columns - 1) * GridMetrics.columnSpacing
    #expect(abs(total - available) < 1.0)
    // Wider than design tile — proves we are not capping at 132.
    #expect(cell.width > GridMetrics.tileWidth)
}

/// Layout occupancy = full 2×2 cells (live tile metrics).
@Test func enlargedSpanMatchesTwoCellBox() {
    let tileW: CGFloat = 160
    let tileH: CGFloat = 140
    let span = GridMetrics.enlargedSpan(
        tileWidth: tileW,
        tileHeight: tileH,
        columnSpacing: 24,
        rowSpacing: 34
    )
    #expect(span.width == tileW * 2 + 24)
    #expect(span.height == tileH * 2 + 34)
}

/// Dock-visible mode must reserve the Dock's screen-space strip so the grid
/// stops above it instead of laying tiles out underneath it.
@Test func dockReservedHeightMatchesVisibleFrameGap() {
    // Dock at the bottom reserves 70pt: visibleFrame starts 70pt above frame.
    #expect(GridMetrics.dockReservedHeight(coverDock: false, screenFrameMinY: 0, visibleFrameMinY: 70) == 70)
    // Cover-Dock mode renders above the Dock's window level — no reservation.
    #expect(GridMetrics.dockReservedHeight(coverDock: true, screenFrameMinY: 0, visibleFrameMinY: 70) == 0)
    // No Dock reservation (e.g. auto-hidden) — visibleFrame matches frame.
    #expect(GridMetrics.dockReservedHeight(coverDock: false, screenFrameMinY: 0, visibleFrameMinY: 0) == 0)
}

/// Visible chrome width = A-icon-left → B-icon-right, not full cell padding.
@Test func enlargedChromeWidthMatchesIconPair() {
    let tileW: CGFloat = 160
    let icon: CGFloat = 104
    let colSp: CGFloat = 24
    // Math: tileW + colSp + icon  (see EnlargedFolderTileView)
    let chromeW = tileW + colSp + icon
    let layoutW = tileW * 2 + colSp
    let inset = (tileW - icon) / 2
    #expect(chromeW == layoutW - inset * 2)
    #expect(chromeW < layoutW)
}
