import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let overlay = OverlayWindowController()
    private var menuBarController: MenuBarController?
    private var hotKeyManager: GlobalHotKeyManager?
    private var updateService: UpdateService?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Two iLaunch.app copies (e.g. /Applications and a locally built
        // dist/) share the same bundle identifier, so `pkill -x iLaunch`
        // during a rebuild can't distinguish them and two live processes can
        // end up racing writes to the same layout.json, silently clobbering
        // the user's custom folders. Refuse to run a second instance:
        // activate the existing one and quit instead.
        if let bundleID = Bundle.main.bundleIdentifier {
            let myPID = ProcessInfo.processInfo.processIdentifier
            let others = NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleID)
                .filter { $0.processIdentifier != myPID }
            if let existing = others.first {
                DiagLog.write("applicationDidFinishLaunching: duplicate instance pid=\(myPID) bundle=\(Bundle.main.bundlePath) — activating existing pid=\(existing.processIdentifier) bundle=\(existing.bundleURL?.path ?? "?") and quitting")
                existing.activate()
                NSApp.terminate(nil)
                return
            }
        }
        NSApp.setActivationPolicy(.regular)
        // Apply the user's chosen app icon to the Dock.
        let prefs = (try? PreferencesStore().load()) ?? .default
        DiagLog.configure(enabled: prefs.diagLoggingEnabled)
        IconSwitcher.apply(prefs.appIconStyle)
        LoginItemService.apply(prefs.launchAtLogin)
        // Must run before UpdateService() below — Sparkle's own alert text
        // resolves its language the moment its bundle is first touched, so
        // the AppleLanguages override needs to already be in place.
        Localizer.setLanguage(prefs.language)
        updateService = UpdateService()
        // Hotkey must open (or toggle) and then re-assert keyboard focus —
        // Carbon hotkeys fire while another app is frontmost.
        hotKeyManager = GlobalHotKeyManager { [overlay] in
            DispatchQueue.main.async {
                overlay.toggle()
            }
        }
        hotKeyManager?.start(keyCode: prefs.hotKeyCode, modifiers: prefs.hotKeyModifiers)
        menuBarController = MenuBarController(overlay: overlay, hotKeyManager: hotKeyManager, updateService: updateService)
        // Launch straight into the full-screen launchpad overlay.
        overlay.show()
    }

    /// Dock icon click: always open fullscreen launchpad.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        overlay.show()
        return true
    }
}
