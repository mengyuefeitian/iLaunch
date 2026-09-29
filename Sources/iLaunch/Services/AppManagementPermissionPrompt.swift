import AppKit

/// Guides the user back to Settings > Privacy & Security > App Management
/// after a fresh install or an update.
///
/// TCC stores each grant together with the app's designated requirement.
/// An ad-hoc signature (`codesign --sign -`) yields `cdhash H"..."`, which
/// changes on every build, so every update used to look like a new app and
/// the grant was reset. Builds are now signed with a stable self-signed
/// identity ("iLaunch Local Signing"), giving the requirement
/// `identifier "com.ilaunch.iLaunch" and certificate leaf = H"..."`, which
/// stays constant across builds (see docs/codesigning.md).
///
/// The first release under that identity is a one-time migration: the stored
/// old cdhash requirement can never match, so the user must re-grant once.
/// The per-version gating below still prompts on every version change; it is
/// cheap, and covers fresh installs too.
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

    /// One-time migration wording: this is the last manual re-grant.
    static let informativeText = "iLaunch 已改用固定的签名身份，这是最后一次需要重新授权：此后更新将保留「App 管理」权限。请前往「系统设置 > 隐私与安全 > App 管理」，如果列表中已有旧的 iLaunch，请先点「−」移除，再重新添加并开启 iLaunch（仅切换开关不会刷新旧记录），否则拖动应用到废纸篓将无法使用。"

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
        alert.informativeText = informativeText
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")

        // .floating (level 3) was not enough — confirmed live: a Terminal
        // window and an already-open Finder window both still painted over
        // it. Those are ordinary windows (level 0), so this points at some
        // other already-open window's level, not a race — go as high as the
        // overlay itself does (same trick OverlayPresentation uses to beat
        // the Dock/menu bar), which is proven to reliably win on this app.
        let window = alert.window
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 2)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.orderFrontRegardless()

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(appManagementURL)
        }
    }
}
