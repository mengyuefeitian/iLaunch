import CoreGraphics
import Testing
@testable import iLaunch

/// Regression: tapping a specific app inside an *enlarged* folder's 3×3
/// member preview, as the very first click after opening the overlay, opened
/// the folder popup instead of launching that app. AppKit's first-click
/// recovery (`OverlayWindowController.performFirstContentClick`) only knew
/// about the folder's own tile frame — the mini member icons weren't tracked
/// at all — so any click anywhere inside the folder's bounds resolved to
/// "open folder". Reproduced here at the pure hit-testing level.
@Test func smallestHitPrefersFolderMemberOverEnclosingFolderFrame() {
    let folder = TileFrameInfo(
        id: "folder:work",
        frame: CGRect(x: 0, y: 0, width: 300, height: 300),
        isFolder: true
    )
    let member = TileFrameInfo(
        id: "com.example.App",
        frame: CGRect(x: 100, y: 100, width: 60, height: 60),
        isFolder: false,
        isFolderMember: true
    )

    let hit = TileHitTesting.smallestHit(in: [folder, member], at: CGPoint(x: 120, y: 120))

    #expect(hit?.id == "com.example.App")
    #expect(hit?.isFolderMember == true)
}

/// A click outside every member icon but still inside the folder's own
/// bounds must fall back to the folder (open-folder behavior is correct
/// there — only a direct hit on a member icon should bypass it).
@Test func smallestHitFallsBackToFolderOutsideMemberIcons() {
    let folder = TileFrameInfo(
        id: "folder:work",
        frame: CGRect(x: 0, y: 0, width: 300, height: 300),
        isFolder: true
    )
    let member = TileFrameInfo(
        id: "com.example.App",
        frame: CGRect(x: 100, y: 100, width: 60, height: 60),
        isFolder: false,
        isFolderMember: true
    )

    let hit = TileHitTesting.smallestHit(in: [folder, member], at: CGPoint(x: 10, y: 10))

    #expect(hit?.id == "folder:work")
}

/// A hidden (non-active) carousel page's member icons must not be present in
/// `tileFrames` at all — otherwise two entries at the same slot with
/// different ids would make the "smallest wins" pick nondeterministic.
/// `EnlargedFolderTileView` enforces this via `TileFramePreferenceModifier`'s
/// `enabled` flag; this test documents the invariant `smallestHit` relies on.
@Test func smallestHitPicksDeterministicallyAmongEqualSizedFrames() {
    let a = TileFrameInfo(id: "a", frame: CGRect(x: 0, y: 0, width: 40, height: 40), isFolder: false, isFolderMember: true)
    let b = TileFrameInfo(id: "b", frame: CGRect(x: 0, y: 0, width: 40, height: 40), isFolder: false, isFolderMember: true)

    let hit = TileHitTesting.smallestHit(in: [a, b], at: CGPoint(x: 20, y: 20))

    // Both are equal area; `min` deterministically keeps the first. Only one
    // should ever be present in practice (see EnlargedFolderTileView).
    #expect(hit?.id == "a")
}

/// Regression: as the very first click after opening the overlay, a click in
/// the *blank padding* around an app icon — clearly outside the icon/title,
/// but still inside the tile's full 132×150 layout slot — wrongly launched
/// that app. `OverlayWindowController.performFirstContentClick` was hit-testing
/// against `tileFrames`, whose reported frame is the full layout slot
/// (including blank cell padding), not the icon+title's actual `contentShape`
/// bounds that normal SwiftUI taps respect. The fix hit-tests against
/// `tileActiveFrames` instead, whose frames are the tight, contentShape-aligned
/// bounds — reproduced here at the pure hit-testing level.
@Test func smallestHitIgnoresBlankTilePaddingOutsideActiveFrame() {
    // Full layout slot (what `tileFrames` reports): 132×150, centered so the
    // icon (see below) sits inside it with padding on every side.
    let looseSlotFrame = CGRect(x: 0, y: 0, width: 132, height: 150)
    // Actual clickable icon+title bounds (what `tileActiveFrames` reports):
    // narrower and shorter than the slot, per AppIconView's real layout.
    let tightActiveFrame = CGRect(x: 14, y: 10, width: 104, height: 124)

    // A point clearly inside the loose slot's padding, but outside the tight
    // active frame — e.g. near the tile's bottom-right corner.
    let paddingPoint = CGPoint(x: 128, y: 146)
    #expect(looseSlotFrame.contains(paddingPoint))
    #expect(!tightActiveFrame.insetBy(dx: -6, dy: -6).contains(paddingPoint))

    let loose = TileFrameInfo(id: "com.example.App", frame: looseSlotFrame, isFolder: false)
    let tight = TileFrameInfo(id: "com.example.App", frame: tightActiveFrame, isFolder: false)

    // Old behavior (bug): hit-testing the loose slot wrongly matches.
    #expect(TileHitTesting.smallestHit(in: [loose], at: paddingPoint)?.id == "com.example.App")

    // Fixed behavior: hit-testing the tight active frame correctly finds
    // nothing, so the click falls through to blank-area dismiss.
    #expect(TileHitTesting.smallestHit(in: [tight], at: paddingPoint) == nil)
}
