import AppKit
import SwiftUI

/// A Launchpad-style zoomed folder: a dark frosted panel listing the contained
/// apps in a grid. The title is click-to-edit. Tapping the dimmed backdrop
/// closes it without dismissing the whole Launchpad.
struct FolderPopupView: View {
    let item: LaunchpadDisplayItem
    let onLaunch: (AppRecord) -> Void
    let onRename: (String) -> Void
    let onTrash: (AppRecord) -> Void
    let onClose: () -> Void
    /// Invoked after the close scale/fade finishes so the parent can nil `openFolder`.
    var onCloseAnimationFinished: (() -> Void)? = nil
    /// When this value increases while the popup is visible, play the close animation.
    var closeEpoch: Int = 0
    var animate: Bool = true
    var wallpaperImage: NSImage? = nil
    var backgroundBlur: Double = 0.72

    var iconSizeLevel: UserPreferences.IconSizeLevel = .large

    // Edit mode support
    var editMode: Bool = false
    var editDragID: String? = nil
    var editDragTranslation: CGSize = .zero
    var onEnterEditMode: (() -> Void)? = nil
    var onCancelEditMode: (() -> Void)? = nil
    /// Called mid-drag once the pointer leaves the folder — closes popup and
    /// starts a floating ghost under the cursor.
    var onDragOutBegan: ((String, CGPoint) -> Void)? = nil
    /// Called on drop after drag-out (or local reorder-out).
    var onDragOutEnded: ((String, CGPoint) -> Void)? = nil
    /// Called during drag to reorder an app within the folder.
    var onReorder: ((String, Int) -> Void)? = nil
    /// Called when a folder-interior reorder drag ends (to persist layout).
    var onReorderEnded: (() -> Void)? = nil
    /// Reports panelFrame changes so the AppKit click monitor can tell
    /// outside-panel backdrop clicks (dismiss) from inside-panel clicks
    /// (member tap / reorder / drag-out, which must reach SwiftUI).
    var onPanelFrameChanged: ((CGRect) -> Void)? = nil
    /// Grid tile frame in overlay coordinates (origin top-left) — zoom origin/target.
    var sourceFrame: CGRect = .zero
    /// Full overlay size for computing the panel’s resting center.
    var overlaySize: CGSize = .zero

    @State private var isEditingName = false
    @State private var draftName = ""
    @State private var leftFolder = false
    @State private var memberFrames: [String: CGRect] = [:]
    @State private var reorderDragID: String? = nil
    @State private var folderDragLocation: CGPoint = .zero
    @State private var panelFrame: CGRect = .zero
    /// 0 = parked on source tile, 1 = fully open at screen center.
    @State private var progress: CGFloat = 0
    @State private var isClosing = false
    @State private var closeGeneration = 0
    @FocusState private var nameFieldFocused: Bool

    private var folderTileWidth: CGFloat { GridMetrics.tileWidth * iconSizeLevel.multiplier }
    private var folderIconSize: CGFloat { 88 * iconSizeLevel.multiplier }
    private var folderTileHeight: CGFloat { 128 * iconSizeLevel.multiplier }

    private var panelWidth: CGFloat { 5 * folderTileWidth + 4 * 16 + 52 }

    /// Estimate resting panel height so we can map source tile → full panel scale.
    private var estimatedPanelHeight: CGFloat {
        let columns = 5
        let rows = max(1, min(4, (item.members.count + columns - 1) / columns))
        let titleBlock: CGFloat = 26 + 28
        let vSpacing: CGFloat = 20
        let grid =
            CGFloat(rows) * folderTileHeight
            + CGFloat(max(0, rows - 1)) * 24
            + 26
        return titleBlock + vSpacing + min(560, grid)
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.fixed(folderTileWidth), spacing: 16), count: 5)
    }

    private var openSpring: Animation {
        .spring(response: 0.40, dampingFraction: 0.86)
    }

    private var closeSpring: Animation {
        .spring(response: 0.32, dampingFraction: 0.92)
    }

    private var closeDuration: TimeInterval { 0.38 }
    /// Hard cap so a hung spring cannot leave a blurred shell forever.
    private var openWatchdog: TimeInterval { 0.70 }
    private var closeWatchdog: TimeInterval { 0.55 }

    /// How much of the full 5-col popup is shown (stays 3×3 near the tile).
    private var expandedContentReveal: CGFloat {
        let t = (progress - 0.28) / 0.45
        let x = min(1, max(0, t))
        return x * x * (3 - 2 * x)
    }

    /// Light motion haze — opacity only. GPU `blur` on full folder grids was
    /// freezing the main thread (clicks / Esc / scroll all dead).
    private var transitDim: Double {
        guard animate else { return 0 }
        // Peaks mid-flight, 0 when fully open or fully closed.
        let p = Double(progress)
        return 0.18 * (4 * p * (1 - p))
    }

    /// Scale + offset: tile frame → screen center.
    private var zoomTransform: (scale: CGFloat, offset: CGSize) {
        let hasSource = sourceFrame.width > 2 && sourceFrame.height > 2
            && overlaySize.width > 2 && overlaySize.height > 2
        guard hasSource else {
            let s = 0.40 + 0.60 * progress
            return (s, .zero)
        }

        let panelW = panelWidth
        let panelH = max(120, estimatedPanelHeight)
        let startScale = max(
            0.12,
            min(sourceFrame.width / panelW, sourceFrame.height / panelH)
        )
        let scale = startScale + (1 - startScale) * progress
        let finalCenter = CGPoint(x: overlaySize.width / 2, y: overlaySize.height / 2)
        let sourceCenter = CGPoint(x: sourceFrame.midX, y: sourceFrame.midY)
        let offset = CGSize(
            width: (sourceCenter.x - finalCenter.x) * (1 - progress),
            height: (sourceCenter.y - finalCenter.y) * (1 - progress)
        )
        return (scale, offset)
    }

    var body: some View {
        let zoom = zoomTransform
        let reveal = expandedContentReveal
        let fullyOpen = progress > 0.97 && !isClosing
        ZStack {
            // Real dismiss for outside-panel clicks happens in AppKit.
            Color.black.opacity(0.45)
                .opacity(Double(progress))
                .overlay(Color.white.opacity(transitDim))
                .contentShape(Rectangle())
                .onTapGesture {
                    if editMode {
                        onCancelEditMode?()
                    } else {
                        beginDismiss()
                    }
                }
                // Always hittable once mostly open so a stuck shell can still be dismissed.
                .allowsHitTesting(progress > 0.5 && !isClosing)

            ZStack {
                // Always-light 3×3 chrome near the tile (no heavy member grid).
                compactTileLayer
                    .opacity(Double(1 - reveal))
                    .allowsHitTesting(false)

                // Mount the expensive 5-col panel only once reveal starts —
                // building LazyVGrid + wallpaper blur every frame was a hang source.
                if reveal > 0.02 {
                    expandedPanelLayer
                        .opacity(Double(reveal))
                        .allowsHitTesting(fullyOpen)
                }
            }
            .frame(width: panelWidth, height: max(120, estimatedPanelHeight))
            // Soft “haze” via dim overlay instead of GPU blur of the whole tree.
            .overlay(Color.white.opacity(transitDim * 0.6).allowsHitTesting(false))
            .scaleEffect(zoom.scale, anchor: .center)
            .offset(zoom.offset)
            .background {
                // Report hit frame ONLY when fully open — never during transit
                // (avoids Observable feedback loops with viewModel.folderPanelFrame).
                GeometryReader { geo in
                    Color.clear
                        .onChange(of: fullyOpen) { _, open in
                            if open {
                                let f = geo.frame(in: .named("overlay"))
                                panelFrame = f
                                onPanelFrameChanged?(f)
                                DiagLog.write("folderPanel fullyOpen frame=\(NSStringFromRect(f))")
                            } else if panelFrame != .zero {
                                panelFrame = .zero
                                onPanelFrameChanged?(.zero)
                            }
                        }
                        .onAppear {
                            if fullyOpen {
                                let f = geo.frame(in: .named("overlay"))
                                panelFrame = f
                                onPanelFrameChanged?(f)
                            }
                        }
                }
            }

            if let dragID = reorderDragID,
               let dragMember = item.members.first(where: { $0.id == dragID }),
               animate, fullyOpen {
                RealAppIcon(record: dragMember)
                    .frame(width: folderIconSize, height: folderIconSize)
                    .scaleEffect(1.15)
                    .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
                    .opacity(0.9)
                    .position(folderDragLocation)
                    .allowsHitTesting(false)
                    .zIndex(10)
            }
        }
        .onAppear { playOpenAnimationIfNeeded() }
        .onChange(of: closeEpoch) { _, _ in
            beginDismiss()
        }
    }

    /// 3×3 closed-folder chrome — always a *small* square icon look (not a
    /// stretched 2×2 panel). Mid-zoom shells read as normal folder tiles.
    private var compactTileLayer: some View {
        let panelH = max(120, estimatedPanelHeight)
        // Prefer the grid tile's own size so open/close match the real icon.
        let fromSource = min(sourceFrame.width, sourceFrame.height)
        let side = max(72, min(fromSource > 2 ? fromSource * 0.92 : 110, min(panelWidth, panelH) * 0.42))
        return ZStack {
            Color.clear
            FolderTileView(members: item.members, size: side)
        }
        .frame(width: panelWidth, height: panelH)
    }

    /// Full open folder panel (title + 5-column member grid).
    private var expandedPanelLayer: some View {
        VStack(spacing: 20) {
            titleView
                .padding(.top, 26)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 24) {
                    ForEach(item.members) { member in
                        folderMemberCell(member: member)
                    }
                }
                .coordinateSpace(name: "folderGrid")
                .padding(.horizontal, 26)
                .padding(.bottom, 26)
            }
            .frame(maxHeight: 560)
        }
        .frame(width: panelWidth)
        .frame(maxHeight: max(120, estimatedPanelHeight))
        .modifier(FolderPanelBackdrop(wallpaperImage: wallpaperImage))
    }

    private func playOpenAnimationIfNeeded() {
        // Always reset local close flags — view identity is per folder id, but
        // be defensive if SwiftUI ever reuses storage.
        isClosing = false
        closeGeneration &+= 1
        let openGen = closeGeneration
        DiagLog.write(
            "folderOpen begin id=\(item.id) animate=\(animate) source=\(NSStringFromRect(sourceFrame))"
        )
        if animate {
            progress = 0
            withAnimation(openSpring) {
                progress = 1
            }
            // Watchdog: if spring stalls, snap open so UI stays usable.
            DispatchQueue.main.asyncAfter(deadline: .now() + openWatchdog) {
                guard openGen == closeGeneration, !isClosing, progress < 0.99 else { return }
                DiagLog.write("folderOpen WATCHDOG snap progress=\(progress) → 1")
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) { progress = 1 }
            }
        } else {
            progress = 1
        }
    }

    /// Zoom back to the source tile (as 3×3), then remove the popup from the tree.
    private func beginDismiss() {
        guard !isClosing else {
            // Second dismiss while animating: finish immediately (matches VM force path).
            DiagLog.write("folderClose beginDismiss re-entry → finish id=\(item.id)")
            finishDismiss()
            return
        }

        DiagLog.write("folderClose begin id=\(item.id) progress=\(progress)")

        guard animate, progress > 0.01 else {
            finishDismiss()
            return
        }

        isClosing = true
        closeGeneration &+= 1
        let generation = closeGeneration
        let closedItemID = item.id
        panelFrame = .zero
        onPanelFrameChanged?(.zero)
        withAnimation(closeSpring) {
            progress = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + closeDuration) {
            guard generation == closeGeneration else { return }
            DiagLog.write("folderClose finished id=\(closedItemID)")
            finishDismiss()
        }
        // Watchdog if asyncAfter is delayed by main-thread load.
        DispatchQueue.main.asyncAfter(deadline: .now() + closeWatchdog) {
            guard generation == closeGeneration, isClosing else { return }
            DiagLog.write("folderClose WATCHDOG force finish id=\(closedItemID)")
            finishDismiss()
        }
    }

    private func finishDismiss() {
        isClosing = false
        if let onCloseAnimationFinished {
            onCloseAnimationFinished()
        } else {
            onClose()
        }
    }

    @ViewBuilder
    private func folderMemberCell(member: AppRecord) -> some View {
        let displayItem = LaunchpadDisplayItem(
            id: member.id,
            title: member.name,
            kind: .app(member)
        )
        let isBeingDragged = (editDragID == member.id && !leftFolder) || reorderDragID == member.id
        let dragTrans = isBeingDragged ? editDragTranslation : .zero
        let jiggleAmp: Double = {
            var generator = SeededGenerator(seed: UInt64(member.id.hashValue & 0xFFFFFFFF))
            return Double.random(in: 0.2...0.35, using: &generator)
        }()

        TimelineView(.animation(minimumInterval: 0.05, paused: !editMode || isBeingDragged)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
            let angle = (editMode && !isBeingDragged) ? sin(phase * 22.0) * jiggleAmp : 0.0
            AppIconView(
                item: displayItem,
                iconSize: folderIconSize,
                tileWidth: folderTileWidth,
                tileHeight: folderTileHeight
                // No onActivate/onDrag* — folder cell owns tap + drag below.
            )
                .scaleEffect(isBeingDragged ? 1.1 : 1.0)
                .shadow(color: isBeingDragged ? .black.opacity(0.4) : .clear, radius: 14, y: 6)
                .rotationEffect(.degrees(angle))
                .offset(dragTrans)
                .opacity(leftFolder && editDragID == member.id ? 0 : (reorderDragID == member.id && animate ? 0 : 1))
                .zIndex(isBeingDragged ? 100 : 0)
        }
            .contentShape(Rectangle())
            .modifier(TileTrashMenu(
                item: displayItem,
                onTrash: { _ in onTrash(member) },
                editMode: editMode
            ))
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.4, maximumDistance: 6)
                    .onEnded { _ in
                        onEnterEditMode?()
                    }
            )
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("overlay"))
                    .onChanged { value in
                        if leftFolder { return }

                        // No DiagLog here: onChanged fires on every pixel of pointer
                        // movement, and DiagLog.write does synchronous file I/O
                        // (open/seek/write/close + a stat() for rotation) — logging
                        // every pixel was the actual cause of dragging feeling
                        // laggy/low-framerate inside an open folder.
                        let distance = hypot(value.translation.width, value.translation.height)
                        guard distance >= 6 else { return }

                        // panelFrame is .zero until first layout — must not treat
                        // that as "outside" or every drag immediately drag-outs.
                        let outsidePanel = panelFrame.width > 1
                            && panelFrame.height > 1
                            && !panelFrame.insetBy(dx: -20, dy: -20).contains(value.location)
                        if outsidePanel {
                            leftFolder = true
                            reorderDragID = nil
                            NotificationCenter.default.post(
                                name: .iLaunchEditDragChanged,
                                object: EditDragUpdate(id: member.id, translation: value.translation)
                            )
                            onDragOutBegan?(member.id, value.location)
                        } else {
                            reorderDragID = member.id
                            folderDragLocation = value.location
                            let targetIndex = computeReorderIndex(
                                dragID: member.id,
                                location: value.location
                            )
                            if let targetIndex,
                               let currentIndex = item.members.firstIndex(where: { $0.id == member.id }),
                               targetIndex != currentIndex {
                                onReorder?(member.id, targetIndex)
                            }
                        }
                    }
                    .onEnded { value in
                        let distance = hypot(value.translation.width, value.translation.height)
                        DiagLog.write("folder drag onEnded distance=\(distance) leftFolder=\(leftFolder)")
                        if distance < 6 {
                            if editMode {
                                onCancelEditMode?()
                            } else {
                                onLaunch(member)
                            }
                        } else if !leftFolder {
                            reorderDragID = nil
                            folderDragLocation = .zero
                            onReorderEnded?()
                            NotificationCenter.default.post(
                                name: .iLaunchEditDragEnded,
                                object: nil
                            )
                        }
                        leftFolder = false
                    }
            )
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear {
                            memberFrames[member.id] = geo.frame(in: .named("overlay"))
                        }
                        .onChange(of: geo.frame(in: .named("overlay"))) { _, newFrame in
                            memberFrames[member.id] = newFrame
                        }
                }
            )
    }

    @ViewBuilder
    private var titleView: some View {
        if isEditingName {
            TextField("文件夹名称", text: $draftName)
                .textFieldStyle(.plain)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .focused($nameFieldFocused)
                .onSubmit { commitName() }
                .onChange(of: nameFieldFocused) { _, focused in
                    if !focused { commitName() }
                }
                .frame(width: 320)
        } else {
            Text(item.title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .onTapGesture {
                    draftName = item.title
                    isEditingName = true
                    nameFieldFocused = true
                }
        }
    }

    private func computeReorderIndex(dragID: String, location: CGPoint) -> Int? {
        let sorted = item.members.enumerated()
            .compactMap { (index, member) -> (Int, CGRect)? in
                guard let frame = memberFrames[member.id] else { return nil }
                return (index, frame)
            }
            .sorted { $0.1.minY < $1.1.minY || ($0.1.minY == $1.1.minY && $0.1.minX < $1.1.minX) }

        for (index, frame) in sorted {
            if location.x < frame.midX && location.y < frame.maxY {
                return index
            }
        }
        return item.members.count - 1
    }

    private func commitName() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != item.title {
            onRename(trimmed)
        }
        isEditingName = false
    }
}

extension Notification.Name {
    static let iLaunchFloatingDragMoved = Notification.Name("iLaunchFloatingDragMoved")
}

/// Opened-folder panel backdrop. On macOS 26+, real Liquid Glass — the system
/// compositor blurs/refracts whatever is actually behind the panel in
/// hardware, so it's both truer to the platform and cheaper per-frame than
/// manually Gaussian-blurring a copy of the wallpaper image on the CPU/GPU
/// side. Pre-26 keeps the original static wallpaper-blur look unchanged.
private struct FolderPanelBackdrop: ViewModifier {
    let wallpaperImage: NSImage?

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .liquidGlass(cornerRadius: 32)
        } else {
            content
                .background(
                    Group {
                        if let wallpaperImage {
                            Image(nsImage: wallpaperImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                // Static backdrop blur — only while fully mounted, not
                                // re-blurred every animation frame of the shell.
                                .blur(radius: 50)
                                .overlay(Color.white.opacity(0.08))
                        } else {
                            Rectangle().fill(.white.opacity(0.12))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        }
    }
}

/// Deterministic random number generator seeded by a UInt64 value.
/// Used to give each tile a stable random jiggle angle.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0xdead_beef : seed
    }

    mutating func next() -> UInt64 {
        // xorshift64
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
