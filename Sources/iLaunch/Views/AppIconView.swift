import AppKit
import SwiftUI

struct AppIconView: View {
    let item: LaunchpadDisplayItem
    var iconSize: CGFloat = 104
    var tileWidth: CGFloat = 132
    var tileHeight: CGFloat = 150
    var showHiddenBadge: Bool = false
    var iconScale: CGFloat = 1.0
    var showName: Bool = true
    /// Frost plate behind the icon while another app is dragged over this one
    /// (create-folder sensing). Same surface as small folder tiles.
    var showFolderCreatePreview: Bool = false
    /// Only icon + title activate. Blank padding inside the tile dismisses.
    var onActivate: (() -> Void)? = nil
    var onLongPress: (() -> Void)? = nil
    var onDragChanged: ((DragGesture.Value) -> Void)? = nil
    var onDragEnded: ((DragGesture.Value) -> Void)? = nil

    /// When embedded in FolderPopupView, all handlers are nil — do NOT attach
    /// empty DragGesture/onTap or they steal the popup's reorder / drag-out.
    private var handlesGridDrag: Bool {
        onDragChanged != nil || onDragEnded != nil
    }

    private var drawnIconSize: CGFloat { iconSize * iconScale }

    private var isFolderItem: Bool {
        if case .folder = item.kind { return true }
        return false
    }

    /// Only report first-click-recovery frames on the main grid (`onActivate`
    /// set); FolderPopupView members and the drag-ghost copy in ContentView
    /// pass no handlers and must not report competing frames under the same
    /// item id.
    private var reportsActiveFrame: Bool { onActivate != nil }

    var body: some View {
        VStack(spacing: showName ? 10 : 0) {
            interactiveIcon
            if showName {
                interactiveTitle
            }
        }
        // Layout reserves the full cell; no full-tile contentShape so blank
        // padding falls through to page-level dismiss.
        .frame(width: tileWidth, height: tileHeight)
    }

    private var interactiveIcon: some View {
        iconView
            .frame(width: drawnIconSize, height: drawnIconSize)
            .overlay(alignment: .bottomTrailing) {
                if showHiddenBadge {
                    Image(systemName: "eye.fill")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(Circle().fill(.black.opacity(0.55)))
                        .offset(x: 2, y: 2)
                }
            }
            .frame(width: iconSize, height: iconSize)
            // Folder-create sensing: frost plate under the target icon only.
            .background {
                if showFolderCreatePreview {
                    RoundedRectangle(cornerRadius: drawnIconSize * 0.22, style: .continuous)
                        .fill(Color.white.opacity(0.14))
                        .overlay(
                            RoundedRectangle(cornerRadius: drawnIconSize * 0.22, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                        )
                        .frame(width: drawnIconSize * 1.22, height: drawnIconSize * 1.22)
                }
            }
            .contentShape(Rectangle())
            // Report the actual icon bounds for AppKit's first-click recovery —
            // scoped to exactly the shape above, not the outer tile cell, or a
            // click in blank padding around the icon would wrongly launch it.
            .modifier(TileActiveFramePreferenceModifier(
                id: item.id,
                isFolder: isFolderItem,
                enabled: reportsActiveFrame
            ))
            .modifier(OptionalIconGestures(
                onActivate: onActivate,
                onLongPress: onLongPress,
                onDragChanged: onDragChanged,
                onDragEnded: onDragEnded,
                attachDrag: handlesGridDrag
            ))
    }

    private var interactiveTitle: some View {
        Text(item.title)
            .font(.callout)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .contentShape(Rectangle())
            // Same reasoning as interactiveIcon above — a second entry under
            // the same id; `smallestHit` matches either rect containing the
            // point, closing the small gap between icon and title that a
            // single icon+title bounding-box frame would have left as a
            // false-positive "hit" (blank but between the two real shapes).
            .modifier(TileActiveFramePreferenceModifier(
                id: item.id,
                isFolder: isFolderItem,
                enabled: reportsActiveFrame
            ))
            .modifier(OptionalIconGestures(
                onActivate: onActivate,
                onLongPress: onLongPress,
                onDragChanged: onDragChanged,
                onDragEnded: onDragEnded,
                attachDrag: handlesGridDrag
            ))
    }

    @ViewBuilder
    private var iconView: some View {
        switch item.kind {
        case .app(let record):
            RealAppIcon(record: record)
        case .folder:
            FolderTileView(members: item.members, size: iconSize * iconScale)
        }
    }
}

/// Attaches tap / long-press / drag only when the corresponding handlers exist.
/// Empty DragGesture must not be installed — it blocks parent gestures (folder popup).
private struct OptionalIconGestures: ViewModifier {
    var onActivate: (() -> Void)?
    var onLongPress: (() -> Void)?
    var onDragChanged: ((DragGesture.Value) -> Void)?
    var onDragEnded: ((DragGesture.Value) -> Void)?
    var attachDrag: Bool

    func body(content: Content) -> some View {
        var view: AnyView = AnyView(content)
        if let onActivate {
            view = AnyView(view.onTapGesture { onActivate() })
        }
        if let onLongPress {
            view = AnyView(view.simultaneousGesture(
                LongPressGesture(minimumDuration: 0.4, maximumDistance: 6)
                    .onEnded { _ in onLongPress() }
            ))
        }
        if attachDrag {
            view = AnyView(view.gesture(
                DragGesture(minimumDistance: 6, coordinateSpace: .named("overlay"))
                    .onChanged { value in onDragChanged?(value) }
                    .onEnded { value in onDragEnded?(value) }
            ))
        }
        return view
    }
}

/// Launchpad-style folder tile: a frosted rounded square showing up to a 3x3
/// preview of the contained apps' icons.
struct FolderTileView: View {
    let members: [AppRecord]
    var size: CGFloat = 104

    private var preview: [AppRecord] { Array(members.prefix(9)) }
    private var cellSize: CGFloat { size * 0.24 }
    private var gridSpacing: CGFloat { size * 0.035 }

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
            .fill(.white.opacity(0.14))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1)
            )
            .overlay(
                Grid(horizontalSpacing: gridSpacing, verticalSpacing: gridSpacing) {
                    GridRow {
                        cell(0)
                        cell(1)
                        cell(2)
                    }
                    GridRow {
                        cell(3)
                        cell(4)
                        cell(5)
                    }
                    GridRow {
                        cell(6)
                        cell(7)
                        cell(8)
                    }
                }
            )
    }

    @ViewBuilder
    private func cell(_ index: Int) -> some View {
        if index < preview.count {
            RealAppIcon(record: preview[index])
                .frame(width: cellSize, height: cellSize)
        } else {
            Color.clear.frame(width: cellSize, height: cellSize)
        }
    }
}

struct RealAppIcon: View {
    let record: AppRecord
    @State private var nsImage: NSImage?

    var body: some View {
        Group {
            if let nsImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Color.clear
            }
        }
        .task(id: record.iconCacheKey) {
            nsImage = await AppIconCache.shared.icon(for: record)
        }
    }
}
