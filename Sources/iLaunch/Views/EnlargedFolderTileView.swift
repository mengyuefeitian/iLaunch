import SwiftUI

/// A folder tile enlarged to 2×2 grid cells, showing a 3×3 icon grid inside.
///
/// **Layout slot** (occupancy map): full 2×2 cells so neighboring apps flow correctly.
/// **Visible chrome**: inset to the icon visual bounds of those two cells so the
/// panel aligns with app icons/titles — not the empty cell padding — and never
/// looks like it "overflows" the icon grid.
///
/// Frost matches **small folder tiles** on the grid (neutral white glass).
/// The colorful wallpaper blur is only for the opened folder popup — leave that alone.
struct EnlargedFolderTileView: View {
    let item: LaunchpadDisplayItem
    var tileWidth: CGFloat = GridMetrics.tileWidth
    var tileHeight: CGFloat = GridMetrics.tileHeight
    var columnSpacing: CGFloat = GridMetrics.columnSpacing
    var rowSpacing: CGFloat = GridMetrics.rowSpacing
    /// Live icon size from the grid (scales with tile height).
    var iconSize: CGFloat = GridMetrics.iconSize
    var showName: Bool = true
    /// When set, tapping a mini member icon invokes this instead of bubbling to the parent chrome tap (open folder).
    var onActivateMember: ((AppRecord) -> Void)? = nil

    @State private var carouselPage = 0
    @State private var autoAdvanceTimer: Timer?

    // MARK: - Layout slot (2×2 cells — do not change occupancy)

    private var layoutWidth: CGFloat { tileWidth * 2 + columnSpacing }
    private var layoutHeight: CGFloat { tileHeight * 2 + rowSpacing }

    // MARK: - Visible chrome (icon-aligned)

    /// Horizontal inset from cell edge to centered icon edge.
    private var iconInsetX: CGFloat { max(0, (tileWidth - iconSize) / 2) }

    /// A-icon-left → B-icon-right  (= tileWidth + columnSpacing + iconSize).
    private var chromeWidth: CGFloat {
        max(iconSize * 2, layoutWidth - iconInsetX * 2)
    }

    /// Label band under an app icon (matches AppIconView spacing + callout).
    private var labelBand: CGFloat { showName ? 28 : 0 }

    /// C-icon-top → D-label-bottom.
    /// Top-aligned content: icon at top of each tile, label under icon.
    private var chromeHeight: CGFloat {
        // From top of row0 icon to top of row1 tile: tileHeight + rowSpacing
        // Then through row1 icon + label band.
        let h = tileHeight + rowSpacing + iconSize + (showName ? 10 + 18 : 0)
        // Never exceed the layout slot.
        return min(layoutHeight, max(iconSize * 2, h))
    }

    private var members: [AppRecord] { item.members }
    private var pageCount: Int { max(1, (members.count + 8) / 9) }

    private var titleHeight: CGFloat { showName ? 18 : 0 }
    private var carouselChromeHeight: CGFloat { pageCount > 1 ? 20 : 0 }
    private var contentPad: CGFloat { 10 }

    private var iconAreaHeight: CGFloat {
        max(
            36,
            chromeHeight
                - titleHeight
                - carouselChromeHeight
                - contentPad * 2
                - (showName ? 6 : 0)
                - (pageCount > 1 ? 4 : 0)
        )
    }

    private var iconAreaWidth: CGFloat {
        max(36, chromeWidth - contentPad * 2)
    }

    private var miniIconSize: CGFloat {
        let byW = (iconAreaWidth - 16) / 3
        let byH = (iconAreaHeight - 16) / 3
        return max(22, min(byW, byH, 64))
    }

    var body: some View {
        // Outer frame = full 2×2 layout slot (occupancy). Chrome centered inside.
        ZStack {
            VStack(spacing: 6) {
                ZStack {
                    if pageCount > 1 {
                        carouselContent
                    } else {
                        iconGrid(members: Array(members.prefix(9)), reportsFrames: true)
                    }
                }
                .frame(width: iconAreaWidth, height: iconAreaHeight)
                .clipped()

                if showName {
                    Text(item.title)
                        .font(.callout)
                        .lineLimit(1)
                        .foregroundStyle(.white)
                        .frame(height: titleHeight)
                        .padding(.horizontal, 8)
                }
            }
            .padding(contentPad)
            .frame(width: chromeWidth, height: chromeHeight)
            // Same surface as FolderTileView on the main grid.
            .background(
                RoundedRectangle(cornerRadius: min(28, chromeWidth * 0.1), style: .continuous)
                    .fill(Color.white.opacity(0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: min(28, chromeWidth * 0.1), style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            )
            .contentShape(Rectangle())
            // Matches this contentShape, not the outer 2×2 layout slot below —
            // see TileActiveFramePreferenceKey doc for why first-click recovery
            // needs this tighter rect instead of the full occupancy frame.
            .modifier(TileActiveFramePreferenceModifier(id: item.id, isFolder: true))
        }
        .frame(width: layoutWidth, height: layoutHeight)
        .onAppear { startAutoAdvance() }
        .onDisappear { stopAutoAdvance() }
    }

    // MARK: - Auto-advance

    private func startAutoAdvance() {
        guard pageCount > 1 else { return }
        stopAutoAdvance()
        autoAdvanceTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    carouselPage = (carouselPage + 1) % pageCount
                }
            }
        }
    }

    private func stopAutoAdvance() {
        autoAdvanceTimer?.invalidate()
        autoAdvanceTimer = nil
    }

    private func resetAutoAdvance() {
        stopAutoAdvance()
        startAutoAdvance()
    }

    // MARK: - Carousel

    private var carouselContent: some View {
        VStack(spacing: 4) {
            ZStack {
                ForEach(0..<pageCount, id: \.self) { page in
                    let start = page * 9
                    let slice = Array(members.dropFirst(start).prefix(9))
                    // Only the visible page reports member frames — every page
                    // stacks its 3×3 slots at the same on-screen positions, so
                    // reporting hidden pages too would leave multiple
                    // same-rect entries with different app ids and make the
                    // AppKit first-click recovery pick one at random.
                    iconGrid(members: slice, reportsFrames: page == carouselPage)
                        .opacity(page == carouselPage ? 1 : 0)
                        .allowsHitTesting(page == carouselPage)
                }
            }
            .frame(maxHeight: .infinity)
            .gesture(
                DragGesture(minimumDistance: 15)
                    .onEnded { value in
                        if value.translation.width < -20, carouselPage < pageCount - 1 {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                carouselPage += 1
                            }
                            resetAutoAdvance()
                        } else if value.translation.width > 20, carouselPage > 0 {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                carouselPage -= 1
                            }
                            resetAutoAdvance()
                        }
                    }
            )

            HStack(spacing: 8) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        carouselPage = max(0, carouselPage - 1)
                    }
                    resetAutoAdvance()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.caption.bold())
                        .foregroundStyle(carouselPage > 0 ? Color.white.opacity(0.9) : Color.white.opacity(0.25))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .disabled(carouselPage == 0)

                HStack(spacing: 5) {
                    ForEach(0..<pageCount, id: \.self) { i in
                        Circle()
                            .fill(i == carouselPage ? Color.white.opacity(0.9) : Color.white.opacity(0.35))
                            .frame(width: 5, height: 5)
                    }
                }

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        carouselPage = min(pageCount - 1, carouselPage + 1)
                    }
                    resetAutoAdvance()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(
                            carouselPage < pageCount - 1 ? Color.white.opacity(0.9) : Color.white.opacity(0.25)
                        )
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .disabled(carouselPage == pageCount - 1)
            }
            .frame(height: carouselChromeHeight)
        }
    }

    // MARK: - 3×3

    private func iconGrid(members: [AppRecord], reportsFrames: Bool) -> some View {
        let spacing: CGFloat = 8
        return Grid(horizontalSpacing: spacing, verticalSpacing: spacing) {
            ForEach(0..<3, id: \.self) { row in
                GridRow {
                    ForEach(0..<3, id: \.self) { col in
                        let index = row * 3 + col
                        if index < members.count {
                            let record = members[index]
                            RealAppIcon(record: record)
                                .frame(width: miniIconSize, height: miniIconSize)
                                .contentShape(Rectangle())
                                .modifier(EnlargedMemberTapModifier(
                                    record: record,
                                    onActivateMember: onActivateMember
                                ))
                                .modifier(TileFramePreferenceModifier(
                                    id: record.id,
                                    isFolder: false,
                                    isFolderMember: true,
                                    enabled: reportsFrames
                                ))
                                // Already the tight, contentShape-aligned frame — also
                                // feed first-click recovery's precise hit test with it.
                                // Gated the same as above: only the visible carousel
                                // page's icons should report (see comment at call site).
                                .modifier(TileActiveFramePreferenceModifier(
                                    id: record.id,
                                    isFolder: false,
                                    isFolderMember: true,
                                    enabled: reportsFrames
                                ))
                        } else {
                            Color.clear.frame(width: miniIconSize, height: miniIconSize)
                        }
                    }
                }
            }
        }
    }
}

/// High-priority tap on a mini icon so parent chrome `.onTapGesture` (open folder) does not fire.
private struct EnlargedMemberTapModifier: ViewModifier {
    let record: AppRecord
    var onActivateMember: ((AppRecord) -> Void)?

    func body(content: Content) -> some View {
        if let onActivateMember {
            content.highPriorityGesture(
                TapGesture().onEnded { onActivateMember(record) }
            )
        } else {
            content
        }
    }
}
