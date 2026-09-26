<div align="center">

<img src="Resources/iLaunch-icon-default.png" width="160" alt="iLaunch" />

# iLaunch

**The Launchpad macOS 26 took away — brought back, native and fast.**

A full-screen visual app grid with folders, instant search, and manual layout,  
built with SwiftUI + AppKit for macOS Tahoe and newer.

[![macOS](https://img.shields.io/badge/macOS-15.0%2B-blue?logo=apple)](https://www.apple.com/macos)
[![Swift](https://img.shields.io/badge/Swift-6.3-orange?logo=swift)](https://www.swift.org)
[![Release](https://img.shields.io/github/v/release/mengyuefeitian/iLaunch?label=release)](../../releases/latest)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

[简体中文](README.md) | **English**

</div>

---

## Why

macOS 26 Tahoe replaced the classic Launchpad with a Spotlight-style Apps  
launcher. It is efficient for searching, but it throws away what made  
Launchpad lovable: **spatial memory**. Knowing *which page, which corner* your  
app lives in is faster than typing every time.

iLaunch restores that experience — a calm, full-screen grid you can  
arrange once and rely on forever.

## Highlights

- **Full-screen grid** — borderless overlay with real system icons and page  
  indicators; customize rows/columns, icon size (S/M/L), and app-name visibility  
  in Settings.
- **Instant search** — live filtering with full **pinyin** support (type `yy`  
  to find 音乐 / Music), keyboard navigation, and tap-anywhere to dismiss.
- **Folders** — drag one app onto another to group; the popup zooms from the  
  tile and back on close; rename, reorder inside, drag out; closed tiles show a  
  3×3 preview; enlarged folders let you launch by tapping a mini icon.
- **Smart Apple folding** — dozens of `com.apple.*` apps tidy into one “Apple”  
  folder on first launch, then quietly fold in new ones without disturbing your  
  layout.
- **Live drag arrange** — tiles make way while you drag; cross-page moves,  
  reorder inside folders, and live gap / create-folder sensing on drag-out;  
  layout is saved and never reshuffled by rescans.
- **Configurable global hotkey** — default `⌥ Space`, changeable in Settings;  
  also open from the menu bar or Dock.
- **Trash / hide** — long-press or right-click to remove or hide an app;  
  launching an app dismisses the overlay immediately (no multi-second freeze).
- **Internationalization** — System language plus Chinese / English / Japanese /  
  Korean / Russian, switchable at runtime.

<div align="center">
<img src="Resources/Screenshots/preview.png" width="800" alt="iLaunch preview" />
</div>

## What's new in v1.8

- **Product renamed: InceptLaunch → iLaunch** — app identity, Settings UI,  
  packaging (`.app` / DMG), bundle ID (`com.ilaunch.iLaunch`), README, and  
  localization all unified under the new name.
- **Seamless data migration** — existing data under  
  `Application Support/InceptLaunch/` is migrated to `iLaunch/` on first  
  launch, with layout and settings preserved.

> Full history: [CHANGELOG](CHANGELOG.md) / [中文](CHANGELOG.zh.md). Latest  
> package: [Releases](../../releases/latest).

## Install

Download the latest `iLaunch-*.dmg` from  
[Releases](../../releases/latest), open it, and drag **iLaunch** into  
**Applications**.

> The current build is ad-hoc signed for personal distribution. On first  
> launch you may need to right-click → **Open** to bypass Gatekeeper.

## Quick start

1. Launch iLaunch (or open from the menu bar / Dock).
2. Press the global hotkey (default `⌥ Space`) to open the grid.
3. Click an app to launch it, or start typing to search.
4. Drag apps to rearrange; drop one onto another to make a folder.
5. Click a folder to open its popup; on enlarged folders, tap a mini icon  
   to launch directly.
6. Open Settings to adjust grid, icons, hotkey, and animation options.
7. Press `Esc` or click empty space to dismiss.

## Roadmap

Where iLaunch is headed, tracked against the original  
[design spec](docs/superpowers/specs/2026-07-20-ilaunch-launchpad-replica-design.md).

| Stage | Focus | Status |
|-------|-------|--------|
| **v0.1** Prototype | App scanning, grid, search, launch, menu bar | ✅ Done |
| **v0.2** Core experience | Full-screen overlay, global hotkey, paging, settings, layout persistence | ✅ Done |
| **v0.3** Manual organization | Drag to reorder, cross-page move, folders, Apple & directory folding | ✅ Done |
| **v0.4** Full replica | Edit mode, move-to-trash, animation polish, keyboard nav | ✅ Done (multi-display still planned) |
| **v1.5** Experience upgrade | Live drag-reorder animation, i18n (ja/ko), settings restructure, hidden apps | ✅ Done |
| **v1.6** Visual & control | Liquid Glass folders, grid/icon settings, Russian, drag-out sensing | ✅ Done |
| **v1.7** Fluid interaction | Folder zoom open/close, mini-icon launch, fast dismiss, first-click fix | ✅ Done |
| **v1.8** Rebrand | InceptLaunch → iLaunch rename, seamless data migration | ✅ Done |
| **v1.9** Auto-update | Sparkle-based auto-update, daily background checks, "Check for Updates…" menu item, one-click install | ✅ Done |
| **v2.0** Stable release | Multi-display & Spaces, performance, first-run guide, signing & notarization | 📋 Planned |

### Coming next

- **Multi-display & Spaces** — predictable overlay placement across monitors,  
  full-screen apps, and Stage Manager, with focus restored on dismiss.
- **Multiple layouts** — switch between Work / Personal / Presentation grids.
- **Old Launchpad migration** — experimentally import pages and folders from  
  the legacy Launchpad database.
- **Signing & notarization** — distribute via Developer ID so Gatekeeper  
  warnings disappear entirely.

## Design principles

iLaunch follows a “Launchpad first” philosophy:

- Manual layout over smart sorting.
- Visual grid over command input.
- Hide over delete.
- Reliable launch over fancy animation.
- Local persistence over cloud sync.

The goal is a trustworthy system companion, not a feature-bloated launcher  
with a shaky core.

## Contributing

This is currently a personal project. Ideas and bug reports are welcome via  
[Issues](../../issues).

## License

Released under the [MIT License](LICENSE). Copyright © 2026.
