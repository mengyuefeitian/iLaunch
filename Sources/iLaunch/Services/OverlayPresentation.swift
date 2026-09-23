import AppKit

/// Pure mapping from the `coverDock` preference to how the overlay window
/// presents itself relative to the Dock and menu bar.
///
/// - Dock-visible (default, `coverDock == false`): the overlay sits one
///   level below the Dock (which stays on top, clickable, like Launchpad)
///   and the menu bar is auto-hidden while the overlay is shown.
/// - Cover-Dock (opt-in, `coverDock == true`): today's legacy behaviour —
///   the overlay sits above the menu bar's window level, covering both the
///   Dock and the menu bar's screen real estate.
enum OverlayPresentation {
    static func windowLevel(coverDock: Bool) -> NSWindow.Level {
        if coverDock {
            return NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)
        }
        return NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) - 1)
    }

    static func presentationOptions(coverDock: Bool) -> NSApplication.PresentationOptions {
        coverDock ? [] : [.autoHideMenuBar]
    }
}
