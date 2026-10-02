import SwiftUI

/// Launchpad-style context menu for tiles: apps get "移到废纸篓"/"隐藏", folders get
/// enlarge/shrink. Right-click triggers the context menu; long-press is reserved
/// for entering edit mode (handled by the tile's own gesture).
struct TileTrashMenu: ViewModifier {
    let item: LaunchpadDisplayItem
    let onTrash: (LaunchpadDisplayItem) -> Void
    var isEnlarged: Bool = false
    var onEnlarge: ((LaunchpadDisplayItem) -> Void)?
    var onShrink: ((LaunchpadDisplayItem) -> Void)?
    var onDissolve: ((LaunchpadDisplayItem) -> Void)?
    var onHide: ((LaunchpadDisplayItem) -> Void)?
    var editMode: Bool = false

    private var isApp: Bool {
        if case .app = item.kind { return true }
        return false
    }

    private var isFolder: Bool {
        if case .folder = item.kind { return true }
        return false
    }

    func body(content: Content) -> some View {
        content
            .contextMenu {
                if editMode {
                    Text(Localizer.t("menu.editModeHint"))
                } else if isApp {
                    Button {
                        onHide?(item)
                    } label: {
                        Label(Localizer.t("menu.hide"), systemImage: "eye.slash")
                    }
                    Button(role: .destructive) {
                        onTrash(item)
                    } label: {
                        Label(Localizer.t("menu.trash"), systemImage: "trash")
                    }
                }
                if isFolder {
                    if isEnlarged {
                        Button {
                            onShrink?(item)
                        } label: {
                            Label(Localizer.t("menu.shrinkFolder"), systemImage: "arrow.down.right.and.arrow.up.left")
                        }
                    } else {
                        Button {
                            onEnlarge?(item)
                        } label: {
                            Label(Localizer.t("menu.enlargeFolder"), systemImage: "arrow.up.left.and.arrow.down.right")
                        }
                    }
                    if let onDissolve, item.id != LayoutStore.appleFolderID {
                        Button(role: .destructive) {
                            onDissolve(item)
                        } label: {
                            Label(Localizer.t("menu.dissolveFolder"), systemImage: "rectangle.stack.badge.minus")
                        }
                    }
                }
            }
    }
}
