import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    /// `SettingsView` uses `NavigationSplitView`, which installs a toolbar on
    /// the window. SwiftUI's toolbar scroll-edge effect assumes the content
    /// view extends under the titlebar/toolbar; without `.fullSizeContentView`
    /// the content view starts below the titlebar, so the blur effect lands
    /// one toolbar-height too low, covering the top of the detail pane.
    static let windowStyleMask: NSWindow.StyleMask = [.titled, .closable, .resizable, .fullSizeContentView]

    /// The window's content rect (unchanged from before `.fullSizeContentView`
    /// was added). The window's on-screen size stays the same as it always
    /// was — `NSWindow` still adds the titlebar/toolbar height on top of this
    /// when computing the frame.
    static let contentSize = NSSize(width: 700, height: 520)

    private var window: NSWindow?
    private weak var viewModel: LaunchpadViewModel?
    private weak var hotKeyManager: GlobalHotKeyManager?
    private var languageObserver: NSObjectProtocol?

    func show(viewModel: LaunchpadViewModel? = nil, hotKeyManager: GlobalHotKeyManager? = nil) {
        self.viewModel = viewModel
        self.hotKeyManager = hotKeyManager
        if let window {
            window.title = Localizer.t("settings.title")
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: Self.windowStyleMask,
            backing: .buffered,
            defer: false
        )
        window.title = Localizer.t("settings.title")
        window.contentView = NSHostingView(rootView: SettingsView(viewModel: viewModel, hotKeyManager: hotKeyManager))
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window

        languageObserver = NotificationCenter.default.addObserver(
            forName: .iLaunchLanguageChanged, object: nil, queue: .main
        ) { [weak window] _ in
            MainActor.assumeIsolated {
                window?.title = Localizer.t("settings.title")
            }
        }
    }
}
