## 1.8.10 - 2026-08-26

### Fixes
- All four app icon variants had a noticeable amount of empty padding around the badge (content sized to ~76% of the 1024×1024 canvas), which read as "not filling the square" in Finder/Quick Look. Regenerated all icon `.icns` files (and their Settings-picker thumbnails) at ~86% content ratio, matching typical macOS app icon sizing, via `script/optimize_icons.sh`.

## 1.8.9 - 2026-08-26

### Fixes
- 1.8.8 only changed the in-app default icon preference, which `IconSwitcher` applies to the Dock icon at runtime — the packaged `.app` bundle's own icon (Finder, DMG window, and the Dock icon before the app finishes launching) still shipped with the old "D" artwork. `script/build_and_run.sh` now sources the bundle icon from `Resources/Icons/icon02.icns` directly, so all of these match "Icon 2" too.

## 1.8.8 - 2026-08-26

### Changes
- Default app icon changed from "D" to "Icon 2" (Settings > Interface > Appearance > App Icon).

## 1.8.7 - 2026-08-26

### Fixes
- With the 1.8.6 "Fill the whole screen (covers the Dock)" toggle turned off, the menu bar was uncovered along with the Dock — `NSScreen.visibleFrame` excludes both, not just the Dock. Fixed by carving only the Dock's own reserved strip out of the full-screen frame, so the overlay still covers the menu bar in both modes and only the Dock's visibility changes with the toggle.

## 1.8.6 - 2026-08-26

### Features
- Settings > General > Launch: new "Fill the whole screen (covers the Dock)" toggle, on by default. Turning it off sizes the launcher overlay to the screen's visible frame instead of the full screen, so the system Dock stays on screen and clickable alongside the grid, matching other launcher-style apps. No system-level Dock hide/show APIs are involved — this only changes whether the overlay's window extends into the Dock's screen area.

## 1.8.5 - 2026-08-21

### Diagnostics
- A user reported merged folders disappearing after relaunch, not reproducible locally. The failure paths that could silently cause this — the one-time `InceptLaunch/` → `iLaunch/` data migration failing, `LayoutPersistenceStore` falling back to a temp directory when Application Support is unreachable, `layout.json` load/save errors, and `pruneApps` dropping folder members not found in a scan — all used `try?` and left no trace. Each now logs its outcome (including the specific app ids `pruneApps` removes and from which folder) to the existing diagnostic log, so the next report can be root-caused from `~/Library/Application Support/iLaunch/logs/incept_diag.log` instead of guessed at. No behavior change.

## 1.8.4 - 2026-08-19

### Fixes
- As the very first gesture after opening the overlay, pressing and dragging an icon to merge it into a folder was completely broken — it launched the app instead. AppKit's first-click recovery path (the same code touched by 1.8.3) resolved any mouseDown landing on a tile immediately and synchronously — launch/open-folder — and consumed the event on the spot, before SwiftUI's own gesture recognizers ever saw it. That made it structurally impossible for that mouseDown to ever become a long-press or a drag. Fixed by having AppKit pass tile hits through to SwiftUI instead of resolving them itself — SwiftUI already correctly sorts out tap vs. long-press vs. drag, including the enlarged-folder-member case fixed in 1.8.2. AppKit keeps direct ownership only of the blank-area dismiss, which stays unreliable in pure SwiftUI.

## 1.8.3 - 2026-08-19

### Fixes
- A first click after opening the overlay, landing in the blank padding around an app/folder icon — clearly off the icon itself, but still inside that tile's full grid-cell bounds — wrongly launched the nearby icon instead of falling through to the expected blank-area dismiss. AppKit's first-click recovery path (`OverlayWindowController.performFirstContentClick`) hit-tested against each tile's full layout-slot frame, not the icon/title's actual clickable region that normal SwiftUI taps respect. Every click after the first already worked correctly. Fixed by hit-testing a new, precisely-scoped "active frame" per tile (icon+title bounds, or an enlarged folder's visible chrome) instead of the full cell.

## 1.8.2 - 2026-08-13

### Fixes
- The very first click after opening the overlay, if it landed on an app icon inside an *enlarged* (2×2) folder's member preview, opened the folder popup instead of launching that app. AppKit's first-click recovery path only knew about the folder's own tile frame — the mini member icons weren't tracked — so any click anywhere inside the folder's bounds was treated as "open folder". Every click after the first one already worked correctly (normal SwiftUI gesture handling already told member taps apart from folder-chrome taps).

## 1.8.1 - 2026-08-13

### Fixes
- Search field dropped the first typed character (AppKit `interpretKeyEvents` was called on the `NSTextField` instead of its field editor, which is the only object that actually implements text insertion)
- Tapping an item in the search results list closed the overlay without launching the app (the AppKit click monitor treated every click while searching as a blank-area dismiss, never checking whether it landed on a result tile)

## 1.8.0 - 2026-07-30

### Features
- Product rename: **InceptLaunch → iLaunch** across app identity, settings UI, packaging (`.app` / DMG), bundle ID (`com.ilaunch.iLaunch`), README, and localization
- Existing Application Support data under `InceptLaunch/` is migrated to `iLaunch/` on first launch

## 1.7.22 - 2026-07-30

### Fixes
- DMG installer layout: curved arrow aligned with arc, Applications drop-target icon restored via Finder alias, `.background` folder hidden off-screen

## 1.7.21 - 2026-07-30

### Features
- Folder popup zooms open from its grid tile and zooms back on close (3×3 tile morph mid-flight)

### Fixes
- First click after opening the overlay (app / folder / blank dismiss) no longer no-ops
- Folder open/close no longer freezes the UI mid-animation or leaves a stuck half-open shell
- Close timers from a previous folder no longer kill a newly opened folder
- Stopped using `NSApp.hide` on dismiss (restore previous frontmost app instead)

## 1.7.13 - 2026-07-30

### Features
- Enlarged (2×2) folder tiles: tap a mini member icon to launch that app without opening the folder popup

### Fixes
- App launch no longer freezes the fullscreen overlay for 2–5 seconds — dismiss first, then open the app asynchronously

## 1.6.19 - 2026-07-26

### Features
- Folder popup uses blurred wallpaper background (Liquid Glass aesthetic)
- Folder tiles scale up when a dragged app enters the acceptance threshold
- Live gap and create-folder sensing when dragging apps out of folders onto the grid
- Settings UI for grid layout, icon size (S/M/L), and show/hide app names
- Dynamic grid rows/columns driven by user preferences
- Russian localization and layout/icon preference keys

### Fixes
- Drag page-flip handoff to floating track, folder handoff ghost, and enlarged row overflow
- Restore folder popup internal reorder and drag-out
- Align search and enlarged folder frost with small-folder styling
- Search frost, editable field, grid spacing, and enlarged folder bounds

## 1.5.5 - 2026-07-25

### Features
- Restructure settings into sidebar navigation with About page
- Add eye badge for hidden apps in search results
- Support drag-to-reorder apps inside folder popups
- Animated live reorder in main grid with tile displacement and floating overlay
- Add implicit spring animation on grid tile position changes
- Add i18n (Japanese / Korean) with live language switch and logging improvements

### Fixes
- Menu bar icon sync, localize search/background labels, center placeholder
- Cache background images to prevent flicker during drag reorder
- Prevent double-move on drop and persist folder reorders
- Resolve variable shadowing in `computeGridTargetIndex` filter
- System app toggle and folder drag-out threshold

### Refactor
- Use ID-based `ForEach` identity for grid animation support
