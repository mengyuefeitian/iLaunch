import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    /// Keep controls and hit testing inside AppKit's standard content region.
    static let windowStyleMask: NSWindow.StyleMask = [.titled, .closable, .resizable]

    static let contentSize = NSSize(width: 780, height: 580)

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
        window.contentMinSize = Self.contentSize
        // Let AppKit coordinate the hosting controller's safe area with the SwiftUI toolbar.
        window.contentViewController = NSHostingController(
            rootView: SettingsView(viewModel: viewModel, hotKeyManager: hotKeyManager)
        )
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
