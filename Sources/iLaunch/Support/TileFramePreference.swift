import SwiftUI

/// A tile's frame together with its identity, so the edit-mode drag can
/// detect overlap with folder tiles and offer "drop into folder".
struct TileFrameInfo: Equatable {
    let id: String
    let frame: CGRect
    let isFolder: Bool
    /// True for a mini app icon inside an *enlarged* folder tile (the 3×3
    /// preview grid), as opposed to the folder tile itself. Lets AppKit's
    /// first-click recovery (see `OverlayWindowController`) tell "tapped a
    /// specific app inside the enlarged folder" apart from "tapped the
    /// folder chrome" — both hits can occur at the same point since the
    /// mini icon sits inside the folder's own frame.
    var isFolderMember: Bool = false
}

/// Preference key that collects the frames of all interactive tile views
/// in the overlay's content-view coordinate space (origin top-left).
struct TileFramePreferenceKey: PreferenceKey {
    static let defaultValue: [TileFrameInfo] = []
    static func reduce(value: inout [TileFrameInfo], nextValue: () -> [TileFrameInfo]) {
        value.append(contentsOf: nextValue())
    }
}

enum TileHitTesting {
    /// Smallest tile frame containing `point` — the tighter hit among
    /// overlapping frames, e.g. a folder-member mini icon sitting inside its
    /// enlarged folder's own (much larger) tile frame. Used by AppKit's
    /// first-click recovery (`OverlayWindowController`), which runs before
    /// SwiftUI's own gesture recognizers have had a chance to see the event.
    static func smallestHit(
        in frames: [TileFrameInfo],
        at point: CGPoint,
        slop: CGFloat = 6
    ) -> TileFrameInfo? {
        let hits = frames.filter { $0.frame.insetBy(dx: -slop, dy: -slop).contains(point) }
        return hits.min { ($0.frame.width * $0.frame.height) < ($1.frame.width * $1.frame.height) }
    }
}
