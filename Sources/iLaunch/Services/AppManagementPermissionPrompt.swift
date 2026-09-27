import AppKit

/// Guides the user back to Settings > Privacy & Security > App Management
/// after a fresh install or an auto-update.
///
/// The app is ad-hoc signed (no paid Developer ID certificate), so its code
/// signature is different on every build. macOS's TCC privacy database keys
/// the "App Management" grant (required for moving other apps to the Trash)
/// off a stable Team ID in the signature — without one, every reinstall or
/// Sparkle update looks like a brand-new app to TCC, and the grant is reset.
/// There is no code-level fix for that (see the Developer ID discussion);
/// this only makes the now-mandatory manual re-grant easier to find.
enum AppManagementPermissionPrompt {
    private static let lastSeenVersionKey = "iLaunchLastSeenVersionForPermissionPrompt"
    private static let appManagementURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles"
    )!

    /// True exactly once per distinct `CFBundleShortVersionString` — covers
    /// both a fresh install (no stored value yet) and every subsequent
    /// update — and persists that this version has now been seen. Pure
    /// aside from the `defaults` write, so the decision itself is testable
    /// without presenting real UI.
    static func shouldPresent(currentVersion: String, defaults: UserDefaults = .standard) -> Bool {
        let lastSeenVersion = defaults.string(forKey: lastSeenVersionKey)
        defaults.set(currentVersion, forKey: lastSeenVersionKey)
        return lastSeenVersion != currentVersion
    }

    @MainActor
    static func presentIfNeeded(bundle: Bundle = .main, defaults: UserDefaults = .standard) {
        guard let currentVersion = bundle.infoDictionary?["CFBundleShortVersionString"] as? String,
              shouldPresent(currentVersion: currentVersion, defaults: defaults) else { return }
        present()
    }

    @MainActor
    static func present() {
        // NSAlert.runModal() only makes the alert modal *within this app* —
        // it does not bring the app itself to the front. Launched via `open`
        // or a relaunch, the app can otherwise sit in the background with an
        // alert no one can see, which is indistinguishable from the overlay
        // z-order bug this was meant to avoid in the first place.
        NSApp.setActivationPolicy(.regular)
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "需要在系统设置中授权 App 管理"
        alert.informativeText = "macOS 会在每次更新或重新安装 iLaunch 后重置「App 管理」权限。请前往「系统设置 > 隐私与安全 > App 管理」，允许 iLaunch 更新或删除其他应用程序，否则拖动应用到废纸篓将无法使用。"
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")
        alert.window.level = .floating
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(appManagementURL)
        }
    }
}
