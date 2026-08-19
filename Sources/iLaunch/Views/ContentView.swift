import AppKit
import SwiftUI

struct ContentView: View {
    let scrollModel: OverlayScrollModel
    @Bindable var viewModel: LaunchpadViewModel
    let preferences: UserPreferences

    @State private var backgroundIndex = 0
    @State private var cachedUploadedImage: NSImage?
    @State private var cachedUploadedPath: String?

    private var isSearching: Bool {
        !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var animEnabled: Bool { !preferences.reduceMotion }

    /// Folder open/close spring — used with `withAnimation` so removal transitions run
    /// even when dismiss comes from AppKit (which does not wrap the assignment).
    private var folderAnimation: Animation? {
        (animEnabled && preferences.animateFolder)
            ? .spring(response: 0.32, dampingFraction: 0.82)
            : nil
    }

    /// Must match AppKit search chrome so results/grid never paint under it.
    private var searchChromeHeight: CGFloat { OverlaySearchChrome.chromeHeight }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                backgroundLayer
                    .frame(width: geo.size.width, height: geo.size.height)
                    .contentShape(Rectangle())
                    .onTapGesture { handleBlankTap() }

                // Hard split: top chrome reserved, bottom content clipped.
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: searchChromeHeight)
                        .allowsHitTesting(false)

                    contentBody
                        .frame(
                            width: geo.size.width,
                            height: max(0, geo.size.height - searchChromeHeight)
                        )
                        .clipped()
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)

                if let folder = viewModel.openFolder {
                    FolderPopupView(
                        item: folder,
                        onLaunch: { record in
                            launchAndDismiss(record)
                        },
                        onRename: { newName in
                            viewModel.renameFolder(id: folder.id, name: newName)
                            viewModel.openFolder?.title = newName
                        },
                        onTrash: { record in
                            Task { await viewModel.moveToTrash(record.id) }
                            viewModel.openFolder?.members.removeAll { $0.id == record.id }
                            if viewModel.openFolder?.members.isEmpty == true {
                                closeFolderPopup()
                            }
                        },
                        onClose: { closeFolderPopup() },
                        onCloseAnimationFinished: {
                            // Only clear if this folder is still open — stale close
                            // timers from a previous popup must not kill a new one.
                            viewModel.finishClosingFolderIfOpen(id: folder.id)
                        },
                        closeEpoch: viewModel.folderCloseEpoch,
                        animate: animEnabled && preferences.animateFolder,
                        wallpaperImage: DesktopWallpaperCapture.currentImage,
                        backgroundBlur: preferences.backgroundBlur,
                        iconSizeLevel: preferences.iconSizeLevel,
                        editMode: viewModel.editMode,
                        editDragID: viewModel.editDragID,
                        editDragTranslation: viewModel.editDragTranslation,
                        onEnterEditMode: {
                            viewModel.editMode = true
                        },
                        onCancelEditMode: {
                            viewModel.editMode = false
                        },
                        onDragOutBegan: { appID, point in
                            viewModel.beginFloatingDragOut(appID: appID, at: point)
                            NotificationCenter.default.post(
                                name: .iLaunchStartFloatingDrag,
                                object: appID
                            )
                        },
                        onDragOutEnded: { _, _ in },
                        onReorder: { appID, newIndex in
                            if case .folder(let f) = folder.kind {
                                if animEnabled && preferences.animateDrag {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        viewModel.liveReorderInFolder(folderID: f.id, appID: appID, toIndex: newIndex)
                                    }
                                } else {
                                    viewModel.liveReorderInFolder(folderID: f.id, appID: appID, toIndex: newIndex)
                                }
                            }
                        },
                        onReorderEnded: {
                            viewModel.persistCurrentLayout()
                        },
                        onPanelFrameChanged: { frame in
                            viewModel.folderPanelFrame = frame
                        },
                        sourceFrame: viewModel.openFolderSourceFrame,
                        overlaySize: geo.size
                    )
                    // Force fresh @State (progress/isClosing) per folder — reusing
                    // the same view left isClosing=true and stuck mid-zoom shells.
                    .id(folder.id)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .zIndex(2)
                }

                if let dragItem = viewModel.gridDragItem {
                    AppIconView(
                        item: dragItem,
                        iconSize: GridMetrics.iconSize,
                        tileHeight: GridMetrics.tileHeight
                    )
                    .scaleEffect(1.15)
                    .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
                    .opacity(0.9)
                    .position(viewModel.gridDragLocation)
                    .allowsHitTesting(false)
                    .zIndex(3)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .coordinateSpace(name: "overlay")
        .onPreferenceChange(TileFramePreferenceKey.self) { frames in
            viewModel.tileFrames = frames
            if !frames.isEmpty {
                viewModel.tileFramesReady = true
            }
        }
        .onPreferenceChange(TileActiveFramePreferenceKey.self) { frames in
            viewModel.tileActiveFrames = frames
        }
        .animation(
            (animEnabled && preferences.animateFolder)
                ? .spring(response: 0.3, dampingFraction: 0.85)
                : nil,
            value: viewModel.openFolder?.id
        )
        .onExitCommand {
            handleBlankTap()
        }
        .task {
            await viewModel.bootstrapScan()
        }
        .onAppear {
            syncScrollHijack()
            loadUploadedImage()
        }
        .onChange(of: viewModel.searchText) { syncScrollHijack() }
        .onChange(of: viewModel.openFolder?.id) { syncScrollHijack() }
        .onChange(of: currentBackgroundPath) { loadUploadedImage() }
        .onReceive(NotificationCenter.default.publisher(for: .iLaunchEditDragChanged)) { note in
            if let update = note.object as? EditDragUpdate {
                viewModel.editDragID = update.id
                viewModel.editDragTranslation = update.translation
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .iLaunchEditDragEnded)) { _ in
            if viewModel.floatingDragItemID == nil {
                viewModel.editDragID = nil
                viewModel.editDragTranslation = .zero
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .iLaunchGridDragMoved)) { note in
            if let update = note.object as? GridDragLocationUpdate {
                if viewModel.gridDragItem == nil {
                    viewModel.gridDragItem = viewModel.visiblePages
                        .flatMap { $0 }
                        .first(where: { $0.id == update.id })
                }
                viewModel.gridDragLocation = update.location
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .iLaunchGridDragEnded)) { _ in
            viewModel.endLiveReorder()
            viewModel.gridDragItem = nil
            viewModel.gridDragLocation = .zero
        }
        .onReceive(NotificationCenter.default.publisher(for: .iLaunchEditModeCancelled)) { _ in
            viewModel.editMode = false
        }
    }

    @ViewBuilder
    private var contentBody: some View {
        if isSearching {
            SearchResultsView(
                results: viewModel.visiblePages.first ?? [],
                onLaunch: { item in handleTap(item) },
                onTrash: { item in
                    Task { await viewModel.moveToTrash(item.id) }
                },
                onHide: { item in
                    viewModel.hideApp(id: item.id)
                },
                onDismiss: { dismiss() },
                animate: animEnabled && preferences.animateSearch
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            LaunchpadGridView(
                pages: viewModel.visiblePages,
                rows: viewModel.gridRows,
                columns: viewModel.gridColumns,
                enlargedFolderIDs: viewModel.enlargedFolderIDs,
                onLaunch: { item in handleTap(item) },
                onLaunchApp: { record in launchAndDismiss(record) },
                openFolderID: viewModel.openFolder?.id,
                onDropItem: { sourceID, target in
                    viewModel.handleDrop(sourceID: sourceID, onto: target)
                },
                onTrash: { item in
                    Task { await viewModel.moveToTrash(item.id) }
                },
                onHide: { item in
                    viewModel.hideApp(id: item.id)
                },
                onEnlarge: { item in
                    viewModel.enlargeFolder(id: item.id)
                },
                onShrink: { item in
                    viewModel.shrinkFolder(id: item.id)
                },
                onDismiss: { dismiss() },
                animatePageFlip: animEnabled && preferences.animatePageFlip,
                animateIcons: animEnabled && preferences.animateIcons,
                animateFolder: animEnabled && preferences.animateFolder,
                animateDrag: animEnabled && preferences.animateDrag,
                iconSizeLevel: preferences.iconSizeLevel,
                showAppNames: preferences.showAppNames,
                onPageChange: { newPage in
                    viewModel.currentPage = newPage
                    if preferences.backgroundMode == .uploaded && preferences.autoCarousel {
                        advanceBackground()
                    }
                },
                editMode: viewModel.editMode,
                editDragID: viewModel.editDragID,
                editDragTranslation: viewModel.editDragTranslation,
                onEnterEditMode: {
                    viewModel.editMode = true
                },
                onCancelEditMode: {
                    viewModel.editMode = false
                },
                onMoveApp: { sourceID, targetPage, targetIndex in
                    viewModel.moveAppInGrid(sourceID: sourceID, targetPage: targetPage, targetIndex: targetIndex)
                },
                onResolveDrop: { sourceID, point, translation, page, localIndex in
                    viewModel.resolveDrop(
                        sourceID: sourceID,
                        at: point,
                        translation: translation,
                        page: page,
                        sourceIndex: localIndex
                    )
                },
                onLiveReorder: { draggedID, toIndex, page in
                    viewModel.beginLiveReorder(draggedID: draggedID, page: page)
                    if animEnabled && preferences.animateDrag {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            viewModel.liveReorder(draggedID: draggedID, toIndex: toIndex, page: page)
                        }
                    } else {
                        viewModel.liveReorder(draggedID: draggedID, toIndex: toIndex, page: page)
                    }
                },
                tileFrames: viewModel.tileFrames,
                externalMergeTargetID: viewModel.mergeTargetID,
                externalCurrentPage: viewModel.currentPage,
                onPromoteToFloatingDrag: { itemID, point in
                    // Apps and folders — edge page-flip must not freeze the ghost.
                    viewModel.beginFloatingGridDrag(itemID: itemID, at: point)
                    NotificationCenter.default.post(
                        name: .iLaunchStartFloatingDrag,
                        object: itemID
                    )
                    // Kick live gap / merge sensing immediately on the new page.
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        viewModel.updateFloatingDrag(at: point)
                    }
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contextMenu {
                Button {
                    viewModel.tidyGrid()
                } label: {
                    Label(Localizer.t("menu.tidyGrid"), systemImage: "square.grid.3x3.fill")
                }
            }
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var backgroundLayer: some View {
        switch preferences.backgroundMode {
        case .desktop:
            if let desktopImage = DesktopWallpaperCapture.currentImage {
                ZStack {
                    Image(nsImage: desktopImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                    Rectangle()
                        .fill(.black.opacity(preferences.backgroundBlur))
                }
            } else {
                Rectangle()
                    .fill(.black.opacity(preferences.backgroundBlur))
                    .background(.ultraThinMaterial)
            }
        case .uploaded:
            if let nsImage = cachedUploadedImage {
                ZStack {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                    Rectangle()
                        .fill(.black.opacity(preferences.backgroundBlur * 0.5))
                }
                .transition(.opacity)
            } else {
                Rectangle()
                    .fill(.black.opacity(preferences.backgroundBlur))
                    .background(.ultraThinMaterial)
            }
        }
    }

    private var currentBackgroundPath: String? {
        guard !preferences.backgroundImages.isEmpty else { return nil }
        let idx = backgroundIndex % preferences.backgroundImages.count
        return preferences.backgroundImages[idx]
    }

    private func advanceBackground() {
        guard preferences.backgroundImages.count > 1 else { return }
        backgroundIndex = (backgroundIndex + 1) % preferences.backgroundImages.count
    }

    private func loadUploadedImage() {
        let path = currentBackgroundPath
        guard path != cachedUploadedPath else { return }
        cachedUploadedPath = path
        cachedUploadedImage = path.flatMap { NSImage(contentsOfFile: $0) }
    }

    private func handleBlankTap() {
        // Order: jiggle → folder → exit fullscreen (including while searching).
        if viewModel.editMode {
            viewModel.editMode = false
        } else if viewModel.openFolder != nil {
            DiagLog.write("handleBlankTap closing folder")
            closeFolderPopup()
        } else if viewModel.floatingDragItemID == nil {
            dismiss()
        }
    }

    /// User dismiss (backdrop / Esc / blank). FolderPopupView plays scale-out,
    /// then `finishClosingFolder` removes it. Launch / drag-out still clear immediately.
    private func closeFolderPopup() {
        viewModel.requestCloseFolder()
    }

    private func syncScrollHijack() {
        scrollModel.update(isSearching: isSearching, isFolderOpen: viewModel.openFolder != nil)
    }

    /// Dismiss the overlay first, then open the app on the next main turn.
    /// Synchronous `NSWorkspace.open` must never block hide (cold start 2–5s).
    private func launchAndDismiss(_ record: AppRecord) {
        // Instant dismiss — no zoom-back when leaving Launchpad to open an app.
        viewModel.finishClosingFolder()
        dismiss()
        DispatchQueue.main.async {
            _ = AppLauncher().launch(record)
        }
    }

    private func handleTap(_ item: LaunchpadDisplayItem) {
        switch item.kind {
        case .app(let record):
            launchAndDismiss(record)
        case .folder:
            // Capture tile frame then open — zoom animation lives in FolderPopupView.
            viewModel.openFolderPopup(item)
        }
    }

    private func dismiss() {
        NotificationCenter.default.post(name: .iLaunchDismiss, object: nil)
    }
}

extension Notification.Name {
    static let iLaunchStartFloatingDrag = Notification.Name("iLaunchStartFloatingDrag")
    static let iLaunchClearSearch = Notification.Name("iLaunchClearSearch")
}
