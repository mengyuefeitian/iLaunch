import SwiftUI

/// Search results grid — same 7-column fixed tile metrics as the main launchpad
/// grid, centered (not stretched to the screen edges).
struct SearchResultsView: View {
    let results: [LaunchpadDisplayItem]
    let onLaunch: (LaunchpadDisplayItem) -> Void
    let onTrash: (LaunchpadDisplayItem) -> Void
    let onHide: (LaunchpadDisplayItem) -> Void
    let onDismiss: () -> Void
    var animate: Bool = true

    private let columns = Array(
        repeating: GridItem(.fixed(GridMetrics.tileWidth), spacing: GridMetrics.columnSpacing),
        count: GridMetrics.columns
    )

    private var gridWidth: CGFloat {
        CGFloat(GridMetrics.columns) * GridMetrics.tileWidth
            + CGFloat(GridMetrics.columns - 1) * GridMetrics.columnSpacing
    }

    var body: some View {
        // Blank dismiss is primarily handled by the AppKit click monitor
        // (ScrollView often swallows SwiftUI background taps). Icons still launch.
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: GridMetrics.rowSpacing) {
                ForEach(results) { item in
                    AppIconView(
                        item: item,
                        iconSize: GridMetrics.iconSize,
                        tileWidth: GridMetrics.tileWidth,
                        tileHeight: GridMetrics.tileHeight,
                        showHiddenBadge: item.isHiddenApp,
                        onActivate: { onLaunch(item) }
                    )
                    .frame(width: GridMetrics.tileWidth, height: GridMetrics.tileHeight)
                    .modifier(TileTrashMenu(
                        item: item,
                        onTrash: onTrash,
                        onHide: onHide
                    ))
                    // Reports this tile's frame into the shared "overlay"
                    // coordinate space so the AppKit click monitor can tell a
                    // result tap apart from a blank-area dismiss tap.
                    .modifier(TileFramePreferenceModifier(id: item.id, isFolder: false))
                }
            }
            .frame(width: gridWidth)
            .frame(maxWidth: .infinity) // center the fixed-width grid
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture { onDismiss() }
        .clipped()
        .animation(animate ? .easeInOut(duration: 0.2) : nil, value: results.count)
    }
}
