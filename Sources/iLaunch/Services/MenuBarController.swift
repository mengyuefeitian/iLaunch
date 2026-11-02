import AppKit

@MainActor
final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let overlay: OverlayWindowController
    private weak var hotKeyManager: GlobalHotKeyManager?
    private let settings = SettingsWindowController()
    private let updateService: UpdateService?
    private let statusMenu = NSMenu()
    private var languageObserver: NSObjectProtocol?
    private var iconObserver: NSObjectProtocol?

    private var settingsItem: NSMenuItem!
    private var logsItem: NSMenuItem!
    private var checkForUpdatesItem: NSMenuItem!
    private var quitItem: NSMenuItem!

    init(overlay: OverlayWindowController, hotKeyManager: GlobalHotKeyManager?, updateService: UpdateService?) {
        self.overlay = overlay
        self.hotKeyManager = hotKeyManager
        self.updateService = updateService
        super.init()

        applyIcon()

        settingsItem = NSMenuItem(title: "", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        statusMenu.addItem(settingsItem)

        logsItem = NSMenuItem(title: "", action: #selector(openLogs), keyEquivalent: "")
        logsItem.target = self
        statusMenu.addItem(logsItem)

        checkForUpdatesItem = NSMenuItem(title: "", action: #selector(checkForUpdates), keyEquivalent: "")
        checkForUpdatesItem.target = self
        statusMenu.addItem(checkForUpdatesItem)

        statusMenu.addItem(NSMenuItem.separator())

        quitItem = NSMenuItem(title: "", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        statusMenu.addItem(quitItem)

        refreshMenuTitles()

        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        languageObserver = NotificationCenter.default.addObserver(
            forName: .iLaunchLanguageChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshMenuTitles()
            }
        }

        iconObserver = NotificationCenter.default.addObserver(
            forName: .iLaunchIconChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applyIcon()
            }
        }
    }

    private func applyIcon() {
        let prefs = (try? PreferencesStore().load()) ?? .default
        let name = prefs.appIconStyle.resourceName
        if let url = Bundle.main.url(forResource: name, withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: 18, height: 18)
            statusItem.button?.image = image
        } else if let fallback = NSImage(named: "iLaunch") {
            fallback.size = NSSize(width: 18, height: 18)
            statusItem.button?.image = fallback
        }
    }

    private func refreshMenuTitles() {
        settingsItem.title = Localizer.t("menubar.settings")
        logsItem.title = Localizer.t("menubar.logs")
        checkForUpdatesItem.title = Localizer.t("menubar.checkForUpdates")
        quitItem.title = Localizer.t("menubar.quit")
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            guard let button = statusItem.button else { return }
            let origin = NSPoint(x: 0, y: button.bounds.height + 2)
            statusMenu.popUp(positioning: nil, at: origin, in: button)
            return
        }
        overlay.show()
    }

    @objc private func openSettings() {
        settings.show(viewModel: overlay.exposedViewModel, hotKeyManager: hotKeyManager)
    }

    @objc private func openLogs() {
        guard let logURL = DiagLog.revealableLogURL() else { return }
        NSWorkspace.shared.activateFileViewerSelecting([logURL])
    }

    @objc private func checkForUpdates() {
        Self.performUpdateCheck(
            dismissOverlay: { [overlay] in overlay.hide(reactivatePrevious: false) },
            activateApp: { NSApp.activate(ignoringOtherApps: true) },
            check: { [updateService] in updateService?.checkForUpdates() }
        )
    }

    /// The overlay sits just under the Dock, so Sparkle's alert would open behind it.
    /// Dismiss the overlay and bring the app forward before starting the check.
    static func performUpdateCheck(
        dismissOverlay: () -> Void,
        activateApp: () -> Void,
        check: () -> Void
    ) {
        dismissOverlay()
        activateApp()
        check()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
