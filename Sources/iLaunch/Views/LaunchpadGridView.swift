import SwiftUI

struct LaunchpadGridView: View {
    let pages: [[LaunchpadDisplayItem]]
    let rows: Int
    let columns: Int
    let enlargedFolderIDs: Set<String>
    let onLaunch: (LaunchpadDisplayItem) -> Void
    /// Direct app launch from enlarged-folder mini icons (skips open-folder).
    var onLaunchApp: ((AppRecord) -> Void)? = nil
    /// While a folder popup is open, hide that grid tile so zoom feels continuous.
    var openFolderID: String? = nil
    let onDropItem: (String, LaunchpadDisplayItem) -> Void
    let onTrash: (LaunchpadDisplayItem) -> Void
    let onHide: (LaunchpadDisplayItem) -> Void
    let onEnlarge: (LaunchpadDisplayItem) -> Void
    let onShrink: (LaunchpadDisplayItem) -> Void
    let onDismiss: () -> Void
    var animatePageFlip: Bool = true
    var animateIcons: Bool = true
    var animateFolder: Bool = true
    var animateDrag: Bool = true
    var iconSizeLevel: UserPreferences.IconSizeLevel = .medium
    var showAppNames: Bool = true
    var onPageChange: ((Int) -> Void)? = nil

    // Edit mode — backed by the ViewModel's @Observable properties.
    var editMode: Bool = false
    var editDragID: String? = nil
    var editDragTranslation: CGSize = .zero
    var onEnterEditMode: (() -> Void)? = nil
    /// Explicit cancel (blank tap while jiggling). Must set editMode=false.
    var onCancelEditMode: (() -> Void)? = nil
    var onMoveApp: ((String, Int, Int) -> Void)? = nil
    /// Unified drop: (sourceID, location, translation, page, sourceLocalIndex).
    var onResolveDrop: ((String, CGPoint, CGSize, Int, Int) -> Void)? = nil
    var onLiveReorder: ((String, Int, Int) -> Void)? = nil
    var tileFrames: [TileFrameInfo] = []
    /// Merge target from floating drag-out (folder closed → grid). Combined
    /// with local grid-drag merge sensing for folder-create frost preview.
    var externalMergeTargetID: String? = nil
    /// Keep grid page in sync when floating drag flips pages externally.
    var externalCurrentPage: Int? = nil
    /// Hand off grid drag to AppKit floating tracking after edge page-flip.
    var onPromoteToFloatingDrag: ((String, CGPoint) -> Void)? = nil

    @State private var currentPage = 0
    @State private var dragOffset: CGFloat = 0
    @State private var dragPageOffset: CGFloat = 0
    @State private var lastEdgePageFlip = Date.distantPast
    /// Must leave the edge zone after a flip before another flip can fire
    /// (prevents one drag at the edge from skipping two pages).
    @State private var edgeFlipArmed = true
    @State private var pageWidthCache: CGFloat = 0
    @State private var pageOriginX: CGFloat = 0
    /// True while a tile drag is active (so blank-tap doesn't steal the gesture).
    @State private var isDraggingTile = false
    @State private var hoveredFolderID: String? = nil
    /// App (or folder) under the dragged app when overlap is high enough to
    /// create / join a folder — drives the frost plate preview on the target.
    @State private var mergeTargetID: String? = nil
    /// SwiftUI drag handed off to floating monitor — ignore further gesture events.
    @State private var handoffToFloating = false

    private var activeMergeTargetID: String? {
        mergeTargetID ?? externalMergeTargetID
    }

    var body: some View {
        VStack(spacing: 18) {
            GeometryReader { geo in
                let width = geo.size.width
                // Side margins 150pt each; the middle band is divided evenly among columns.
                let sidePadding: CGFloat = 150
                let gridAreaWidth = geo.size.width - sidePadding * 2
                let gridAreaHeight = geo.size.height
                let cell = GridMetrics.cellSize(
                    rows: rows,
                    columns: columns,
                    availableWidth: gridAreaWidth,
                    availableHeight: gridAreaHeight
                )
                // Fill the middle band — do NOT cap width (that collapsed spacing).
                let tileWidth = cell.width
                let tileHeight = min(cell.height, GridMetrics.tileHeight)
                let iconSize = GridMetrics.iconSize * (tileHeight / GridMetrics.tileHeight)
                HStack(spacing: 0) {
                    ForEach(pages.indices, id: \.self) { index in
                        pageGrid(pages[index], iconSize: iconSize, tileWidth: tileWidth, tileHeight: tileHeight, pageWidth: width, pageIndex: index)
                            .frame(width: width, height: geo.size.height, alignment: .center)
                    }
                }
                .offset(x: -CGFloat(currentPage) * width + dragOffset)
                .animation(
                    (editMode || isDraggingTile)
                        ? nil
                        : (animatePageFlip ? .spring(response: 0.35, dampingFraction: 0.85) : nil),
                    value: currentPage
                )
                // Page swipe only when not in edit mode and not mid-tile-drag.
                .gesture((editMode || isDraggingTile) ? nil : dragGesture(width: width))
                .contentShape(Rectangle())
                .onTapGesture {
                    if editMode {
                        onCancelEditMode?()
                    } else if !isDraggingTile {
                        onDismiss()
                    }
                }
                .background(
                    GeometryReader { g in
                        Color.clear
                            .onAppear {
                                pageWidthCache = width
                                pageOriginX = g.frame(in: .named("overlay")).minX
                            }
                            .onChange(of: width) { _, w in
                                pageWidthCache = w
                                pageOriginX = g.frame(in: .named("overlay")).minX
                            }
                    }
                )
            }
            .clipped()

            PageDots(count: pages.count, current: currentPage) { index in
                goTo(index)
            }
            .opacity(pages.count > 1 ? 1 : 0)
        }
        .onReceive(NotificationCenter.default.publisher(for: .iLaunchPageScroll)) { note in
            let direction = (note.object as? Int) ?? 0
            goTo(currentPage + direction)
        }
        .onReceive(NotificationCenter.default.publisher(for: .iLaunchGoToPage)) { note in
            if let page = note.object as? Int {
                goTo(page)
            }
        }
        // Floating drop ends AppKit tracking; the original SwiftUI DragGesture
        // often never gets onEnded (tile was reparented). Clear handoff flags
        // here or the next drag's onChanged is a no-op until a dummy gesture ends.
        .onReceive(NotificationCenter.default.publisher(for: .iLaunchGridDragEnded)) { _ in
            resetDragHandoffState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .iLaunchEditDragEnded)) { _ in
            resetDragHandoffState()
        }
        .onChange(of: pages.count) {
            currentPage = clamp(currentPage)
        }
        .onChange(of: editMode) { _, _ in
            dragPageOffset = 0
            lastEdgePageFlip = .distantPast
            edgeFlipArmed = true
            resetDragHandoffState()
        }
        .onChange(of: externalCurrentPage) { _, page in
            guard let page, page != currentPage else { return }
            currentPage = clamp(page)
        }
    }

    private func resetDragHandoffState() {
        handoffToFloating = false
        isDraggingTile = false
        dragPageOffset = 0
        edgeFlipArmed = true
    }

    @ViewBuilder
    private func pageGrid(_ page: [LaunchpadDisplayItem], iconSize: CGFloat, tileWidth: CGFloat, tileHeight: CGFloat, pageWidth: CGFloat, pageIndex: Int) -> some View {
        LaunchpadGridLayout(
            columns: columns,
            tileWidth: tileWidth,
            tileHeight: tileHeight,
            minRows: rows
        ) {
            ForEach(page) { item in
                let idx = page.firstIndex(where: { $0.id == item.id }) ?? 0
                tileCell(item: item, localIndex: idx, iconSize: iconSize, tileWidth: tileWidth, tileHeight: tileHeight, pageWidth: pageWidth, pageIndex: pageIndex)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, 150) // matches sidePadding used for cell sizing
        .animation(
            animateDrag ? .spring(response: 0.3, dampingFraction: 0.7) : nil,
            value: page.map(\.id)
        )
    }

    @ViewBuilder
    private func tileCell(item: LaunchpadDisplayItem, localIndex: Int, iconSize: CGFloat, tileWidth: CGFloat, tileHeight: CGFloat, pageWidth: CGFloat, pageIndex: Int) -> some View {
        let enlarged = enlargedFolderIDs.contains(item.id)
        let isBeingDragged = editDragID == item.id
        let dragTrans = isBeingDragged ? editDragTranslation : .zero
        let isFolder: Bool = {
            if case .folder = item.kind { return true }
            return false
        }()
        // Folders look larger — keep rotation tiny so they don't "whip" around.
        let tileJiggleAmplitude: Double = {
            var generator = SeededGenerator(seed: UInt64(item.id.hashValue & 0xFFFFFFFF))
            let range: ClosedRange<Double> = isFolder ? 0.2...0.35 : 0.55...0.9
            return Double.random(in: range, using: &generator)
        }()

        // TimelineView drives jiggle; `layoutEnlarged` MUST be on the Layout's
        // direct child (this outer chain). Putting it only *inside* TimelineView
        // made enlarged folders occupy 1 cell while drawing 2×2 → icons stacked
        // on top of the big folder.
        TimelineView(.animation(minimumInterval: 0.05, paused: !editMode || isBeingDragged)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
            let angle = (editMode && !isBeingDragged)
                ? sin(phase * 22.0) * tileJiggleAmplitude
                : 0.0

            let isMergeTarget = !isBeingDragged && activeMergeTargetID == item.id
            tileView(
                item: item,
                localIndex: localIndex,
                iconSize: iconSize,
                tileWidth: tileWidth,
                tileHeight: tileHeight,
                enlarged: enlarged,
                pageWidth: pageWidth,
                pageIndex: pageIndex,
                showFolderCreatePreview: isMergeTarget && !isFolder
            )
                .scaleEffect(
                    isBeingDragged
                        ? 1.1
                        : (isMergeTarget || (isFolder && hoveredFolderID == item.id) ? 1.08 : 1.0)
                )
                .shadow(color: isBeingDragged ? .black.opacity(0.45) : .clear, radius: 16, y: 8)
                .rotationEffect(.degrees(angle))
                .offset(dragTrans)
                .opacity(tileOpacity(itemID: item.id, isBeingDragged: isBeingDragged))
        }
        // zIndex on the Layout child so the dragged tile paints above folders
        // (not under them mid-drag).
        .zIndex(isBeingDragged ? 1000 : 0)
        .layoutEnlarged(enlarged)
        .modifier(TileTrashMenu(
            item: item,
            onTrash: onTrash,
            isEnlarged: enlarged,
            onEnlarge: onEnlarge,
            onShrink: onShrink,
            onHide: onHide,
            editMode: editMode
        ))
        // No full-tile contentShape / launch gesture: blank cell padding must
        // fall through to page-level dismiss. Activate + drag live on icon/title
        // (or the full enlarged-folder chrome) only.
        .modifier(TileFramePreferenceModifier(id: item.id, isFolder: isFolder))
    }

    private func tileOpacity(itemID: String, isBeingDragged: Bool) -> Double {
        // Hide source tile while its popup is open (zoom continuity).
        if openFolderID == itemID { return 0 }
        if isBeingDragged && animateDrag { return 0 }
        if isBeingDragged { return 0.92 }
        return 1
    }

    /// Shared drag handling for app tiles and enlarged folders.
    private func handleDragChanged(
        item: LaunchpadDisplayItem,
        localIndex: Int,
        pageWidth: CGFloat,
        value: DragGesture.Value
    ) {
        // After edge page-flip handoff, AppKit floating drag owns the gesture.
        if handoffToFloating { return }

        isDraggingTile = true
        let translation = CGSize(
            width: value.translation.width + dragPageOffset,
            height: value.translation.height
        )
        let pageBefore = currentPage
        maybeFlipPageAtEdge(fingerX: value.location.x, pageWidth: pageWidth)

        // Page flipped under a drag (app or folder): SwiftUI DragGesture is bound
        // to the source tile and dies when the strip/item moves. Hand off to the
        // AppKit floating monitor so tracking continues on the new page.
        let sourceIsApp: Bool = {
            if case .app = item.kind { return true }
            return false
        }()
        if currentPage != pageBefore, onPromoteToFloatingDrag != nil {
            handoffToFloating = true
            mergeTargetID = nil
            hoveredFolderID = nil
            onPromoteToFloatingDrag?(item.id, value.location)
            NotificationCenter.default.post(
                name: .iLaunchEditDragChanged,
                object: EditDragUpdate(id: item.id, translation: .zero)
            )
            return
        }

        if animateDrag, let onLiveReorder {
            let targetIndex = computeGridTargetIndex(
                dragID: item.id,
                location: value.location,
                page: currentPage
            )
            let currentIndex = pages[currentPage].firstIndex(where: { $0.id == item.id }) ?? localIndex
            if targetIndex != currentIndex {
                onLiveReorder(item.id, targetIndex, currentPage)
            }
        }

        let folderTarget = tileFrames.first { info in
            info.isFolder
            && info.id != item.id
            && info.frame.insetBy(dx: -10, dy: -10).contains(value.location)
        }
        let newHover = folderTarget?.id
        if newHover != hoveredFolderID {
            withAnimation(animateDrag ? .spring(response: 0.25, dampingFraction: 0.7) : nil) {
                hoveredFolderID = newHover
            }
        }

        // Folder-create / add-to-folder sensing (apps only as drag source).
        // Preview threshold is slightly below the drop merge threshold (50%) so
        // the frost plate appears just before the drop would commit.
        let newMerge: String? = sourceIsApp
            ? mergePreviewTargetID(sourceID: item.id, location: value.location)
            : nil
        if newMerge != mergeTargetID {
            withAnimation(animateDrag ? .spring(response: 0.22, dampingFraction: 0.75) : nil) {
                mergeTargetID = newMerge
            }
        }

        NotificationCenter.default.post(
            name: .iLaunchEditDragChanged,
            object: EditDragUpdate(id: item.id, translation: translation)
        )
        NotificationCenter.default.post(
            name: .iLaunchGridDragMoved,
            object: GridDragLocationUpdate(id: item.id, location: value.location)
        )
    }

    private func handleDragEnded(
        item: LaunchpadDisplayItem,
        localIndex: Int,
        pageIndex: Int,
        value: DragGesture.Value
    ) {
        // Floating handoff owns drop — do not resolve twice.
        if handoffToFloating {
            resetDragHandoffState()
            return
        }

        withAnimation(animateDrag ? .spring(response: 0.25, dampingFraction: 0.7) : nil) {
            hoveredFolderID = nil
            mergeTargetID = nil
        }

        defer {
            isDraggingTile = false
            dragPageOffset = 0
            NotificationCenter.default.post(name: .iLaunchEditDragEnded, object: nil)
            NotificationCenter.default.post(name: .iLaunchGridDragEnded, object: nil)
        }

        let translation = CGSize(
            width: value.translation.width + dragPageOffset,
            height: value.translation.height
        )

        if let onResolveDrop {
            onResolveDrop(item.id, value.location, translation, currentPage, localIndex)
            return
        }

        if currentPage != pageIndex || translation != .zero {
            onMoveApp?(item.id, currentPage, localIndex)
        }
    }

    private func computeGridTargetIndex(dragID: String, location: CGPoint, page: Int) -> Int {
        let pageItems = pages[page]
        let otherFrames = tileFrames
            .filter { frame in
                frame.id != dragID && pageItems.contains(where: { $0.id == frame.id })
            }
            .sorted { a, b in
                let indexA = pageItems.firstIndex(where: { $0.id == a.id }) ?? 0
                let indexB = pageItems.firstIndex(where: { $0.id == b.id }) ?? 0
                return indexA < indexB
            }

        for (rank, info) in otherFrames.enumerated() {
            if location.x < info.frame.midX && location.y < info.frame.maxY {
                return rank
            }
        }
        return pageItems.count - 1
    }

    /// Target tile that would receive a create/join-folder merge if the user
    /// dropped now. Uses the same intersection math as `resolveDrop` (ratio of
    /// dragged rect area). Preview fires a bit earlier than the 50% commit.
    ///
    /// **Must center on the pointer**, not `tileFrame + translation`: live
    /// reorder already moves the source cell in the layout, so adding the full
    /// drag translation double-counts Y and hits the row below the ghost.
    private func mergePreviewTargetID(
        sourceID: String,
        location: CGPoint,
        minRatio: CGFloat = 0.35
    ) -> String? {
        let draggedFrame = DragMergeGeometry.draggedFrame(
            sourceID: sourceID,
            pointer: location,
            tileFrames: tileFrames
        )
        let draggedArea = max(1, draggedFrame.width * draggedFrame.height)
        var bestID: String?
        var bestRatio: CGFloat = 0
        // Exclude enlarged-folder member icons (see LaunchpadViewModel.mergePreviewID).
        for info in tileFrames where info.id != sourceID && !info.isFolderMember {
            let overlap = draggedFrame.intersection(info.frame)
            guard !overlap.isNull, overlap.width > 0, overlap.height > 0 else { continue }
            let ratio = (overlap.width * overlap.height) / draggedArea
            if ratio > bestRatio {
                bestRatio = ratio
                bestID = info.id
            }
        }
        guard bestRatio > minRatio else { return nil }
        return bestID
    }

    private func maybeFlipPageAtEdge(fingerX: CGFloat, pageWidth: CGFloat) {
        let width = pageWidth > 0 ? pageWidth : pageWidthCache
        guard width > 0 else { return }
        let localX = fingerX - pageOriginX
        let edgeZone: CGFloat = 56
        let inLeft = localX < edgeZone
        let inRight = localX > width - edgeZone

        // Hysteresis: after one flip, finger must leave the edge before re-arming.
        if !inLeft && !inRight {
            edgeFlipArmed = true
            return
        }
        guard edgeFlipArmed else { return }

        let now = Date()
        // Slightly longer cooldown so handoff → floating doesn't double-flip.
        guard now.timeIntervalSince(lastEdgePageFlip) > 0.75 else { return }

        if inLeft, currentPage > 0 {
            currentPage -= 1
            dragPageOffset -= width
            lastEdgePageFlip = now
            edgeFlipArmed = false
            onPageChange?(currentPage)
        } else if inRight, currentPage < pages.count - 1 {
            currentPage += 1
            dragPageOffset += width
            lastEdgePageFlip = now
            edgeFlipArmed = false
            onPageChange?(currentPage)
        }
    }

    @ViewBuilder
    private func tileView(
        item: LaunchpadDisplayItem,
        localIndex: Int,
        iconSize: CGFloat,
        tileWidth: CGFloat,
        tileHeight: CGFloat,
        enlarged: Bool,
        pageWidth: CGFloat,
        pageIndex: Int,
        showFolderCreatePreview: Bool = false
    ) -> some View {
        if enlarged, case .folder = item.kind {
            // Tap/drag target is the drawn chrome only — EnlargedFolderTileView's
            // own inner .contentShape(Rectangle()) is already scoped to the
            // icon-aligned chrome bounds, not the full 2×2 layout slot. A
            // .contentShape(Rectangle()) added here would re-widen the target
            // back to the full slot, making the ~20px margin around the chrome
            // (needed so neighboring tiles flow correctly) falsely open the
            // folder instead of falling through to page-level dismiss.
            EnlargedFolderTileView(
                item: item,
                tileWidth: tileWidth,
                tileHeight: tileHeight,
                iconSize: iconSize,
                showName: showAppNames,
                onActivateMember: { record in
                    // IMPORTANT gesture fix: when already in edit mode, ignore mini-icon taps
                    // (do NOT call onCancelEditMode). Parent long-press can set editMode=true and
                    // then finger-up fires TapGesture; cancelling would make long-press-to-jiggle
                    // on mini icons impossible. Chrome .onTapGesture still cancels edit as before.
                    guard !editMode else { return }
                    onLaunchApp?(record)
                }
            )
                .onTapGesture {
                    if editMode {
                        onCancelEditMode?()
                    } else {
                        onLaunch(item)
                    }
                }
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.4, maximumDistance: 6)
                        .onEnded { _ in onEnterEditMode?() }
                )
                .gesture(
                    DragGesture(minimumDistance: 6, coordinateSpace: .named("overlay"))
                        .onChanged { handleDragChanged(item: item, localIndex: localIndex, pageWidth: pageWidth, value: $0) }
                        .onEnded { handleDragEnded(item: item, localIndex: localIndex, pageIndex: pageIndex, value: $0) }
                )
        } else {
            AppIconView(
                item: item,
                iconSize: iconSize,
                tileWidth: tileWidth,
                tileHeight: tileHeight,
                iconScale: iconSizeLevel.multiplier,
                showName: showAppNames,
                showFolderCreatePreview: showFolderCreatePreview,
                onActivate: {
                    if editMode {
                        onCancelEditMode?()
                    } else {
                        onLaunch(item)
                    }
                },
                onLongPress: { onEnterEditMode?() },
                onDragChanged: { handleDragChanged(item: item, localIndex: localIndex, pageWidth: pageWidth, value: $0) },
                onDragEnded: { handleDragEnded(item: item, localIndex: localIndex, pageIndex: pageIndex, value: $0) }
            )
        }
    }

    // MARK: - Normal page drag gesture

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                dragOffset = value.translation.width
            }
            .onEnded { value in
                let threshold = width * 0.12
                var target = currentPage
                if value.translation.width < -threshold {
                    target += 1
                } else if value.translation.width > threshold {
                    target -= 1
                }
                let newPage = clamp(target)
                let changed = newPage != currentPage
                currentPage = newPage
                dragOffset = 0
                if changed {
                    onPageChange?(newPage)
                }
            }
    }

    private func goTo(_ page: Int) {
        let target = clamp(page)
        guard target != currentPage else { return }
        currentPage = target
        onPageChange?(target)
    }

    private func clamp(_ value: Int) -> Int {
        guard pages.count > 0 else { return 0 }
        return min(max(0, value), pages.count - 1)
    }

}

// MARK: - Tile Frame Preference Helper

struct TileFramePreferenceModifier: ViewModifier {
    let id: String
    let isFolder: Bool
    var isFolderMember: Bool = false
    /// False skips reporting entirely — used for an enlarged folder's
    /// carousel pages that are stacked but not currently visible, so their
    /// (identically-positioned, different-id) member frames don't collide
    /// with the active page's.
    var enabled: Bool = true

    func body(content: Content) -> some View {
        if enabled {
            content.background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: TileFramePreferenceKey.self,
                        value: [TileFrameInfo(
                            id: id,
                            frame: proxy.frame(in: .named("overlay")),
                            isFolder: isFolder,
                            isFolderMember: isFolderMember
                        )]
                    )
                }
            }
        } else {
            content
        }
    }
}

// MARK: - Edit Drag Notifications

struct EditDragUpdate {
    let id: String
    let translation: CGSize
}

struct GridDragLocationUpdate {
    let id: String
    let location: CGPoint
}

extension Notification.Name {
    static let iLaunchEditDragChanged = Notification.Name("iLaunchEditDragChanged")
    static let iLaunchEditDragEnded = Notification.Name("iLaunchEditDragEnded")
    static let iLaunchGridDragMoved = Notification.Name("iLaunchGridDragMoved")
    static let iLaunchGridDragEnded = Notification.Name("iLaunchGridDragEnded")
}

/// Launchpad-style page indicator
struct PageDots: View {
    let count: Int
    let current: Int
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 14) {
            ForEach(0..<max(count, 1), id: \.self) { index in
                Circle()
                    .fill(index == current ? Color.white.opacity(0.95) : Color.white.opacity(0.28))
                    .frame(width: 9, height: 9)
                    .scaleEffect(index == current ? 1.25 : 1.0)
                    .contentShape(Circle().inset(by: -6))
                    .onTapGesture { onSelect(index) }
            }
        }
        .padding(.vertical, 8)
        .animation(.easeOut(duration: 0.2), value: current)
    }
}
