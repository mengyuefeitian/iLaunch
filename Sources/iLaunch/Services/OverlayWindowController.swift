import AppKit
import SwiftUI

extension Notification.Name {
    static let iLaunchDismiss = Notification.Name("iLaunchDismiss")
    static let iLaunchPageScroll = Notification.Name("iLaunchPageScroll")
    static let iLaunchFocusSearch = Notification.Name("iLaunchFocusSearch")
    /// Posted when edit mode is cancelled from AppKit (click monitor).
    static let iLaunchEditModeCancelled = Notification.Name("iLaunchEditModeCancelled")
    /// Posted when grid rows/columns settings change so the overlay can re-layout.
    static let iLaunchGridSettingsChanged = Notification.Name("iLaunchGridSettingsChanged")
    /// Absolute page index (Int) for grid while floating drag flips pages.
    static let iLaunchGoToPage = Notification.Name("iLaunchGoToPage")
}

struct OverlayState {
    private(set) var isVisible = false

    mutating func toggle() {
        isVisible.toggle()
    }
}

/// Borderless window that can become key so the search field and Esc work.
final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override var acceptsFirstResponder: Bool { true }
}

/// After `NSApp.hide` → `unhide` + activate, the first click on a normal
/// `NSView` is often treated as “make key only” and never reaches SwiftUI
/// (`onTapGesture` / drag). Returning true here delivers that first click.
private final class FirstMouseView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Same first-mouse fix for the SwiftUI hosting surface (grid / folders / apps).
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class OverlayWindowController {
    private var window: OverlayWindow?
    private var hostingView: FirstMouseHostingView<ContentView>?
    private var dismissObserver: NSObjectProtocol?
    private var floatingDragStartObserver: NSObjectProtocol?
    private var focusSearchObserver: NSObjectProtocol?
    private var scrollMonitor: Any?
    private var clickMonitor: Any?
    private var keyMonitor: Any?
    private var floatingDragMonitor: Any?
    private var floatingGhostView: NSView?
    private let searchChrome = OverlaySearchChrome()
    private let scrollModel = OverlayScrollModel()
    private let viewModel = LaunchpadViewModel()
    private let preferencesStore = PreferencesStore()
    /// After each show(), the first grid click is handled in AppKit — SwiftUI
    /// often never sees that mouseDown (post-hide/activate). Cleared after use.
    private var recoverFirstContentClick = false
    /// App that was frontmost before we stole focus — reactivated on hide.
    private var appToReactivate: NSRunningApplication?

    var exposedViewModel: LaunchpadViewModel { viewModel }

    init() {
        dismissObserver = NotificationCenter.default.addObserver(
            forName: .iLaunchDismiss,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.hide()
            }
        }
        floatingDragStartObserver = NotificationCenter.default.addObserver(
            forName: .iLaunchStartFloatingDrag,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let appID = note.object as? String
            MainActor.assumeIsolated {
                self?.installFloatingDragMonitor(appID: appID)
            }
        }
        focusSearchObserver = NotificationCenter.default.addObserver(
            forName: .iLaunchFocusSearch,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.searchChrome.focus()
            }
        }
        NotificationCenter.default.addObserver(
            forName: .iLaunchClearSearch,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.viewModel.searchText = ""
                self?.searchChrome.setText("")
                self?.searchChrome.blur()
            }
        }
        NotificationCenter.default.addObserver(
            forName: .iLaunchLanguageChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.searchChrome.refreshPlaceholder()
            }
        }
        NotificationCenter.default.addObserver(
            forName: .iLaunchGridSettingsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.viewModel.applyGridSettingsChange()
            }
        }
    }

    func toggle() {
        if let window, window.isVisible {
            hide()
            return
        }
        show()
    }

    func show() {
        // If already visible, just re-assert key focus (e.g. hotkey while open).
        if let existing = window, existing.isVisible {
            activateForKeyboard(existing)
            return
        }

        let screen = NSScreen.main ?? NSScreen.screens.first
        let frame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let window = OverlayWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = false
        // Accept keyboard without a titlebar — critical for hotkey-opened sessions.
        window.acceptsMouseMovedEvents = true

        scrollModel.update(isSearching: false, isFolderOpen: false)
        viewModel.tileFramesReady = false
        viewModel.tileFrames = []
        viewModel.finishClosingFolder()
        viewModel.editMode = false
        viewModel.editDragID = nil
        viewModel.editDragTranslation = .zero
        viewModel.currentPage = 0
        viewModel.searchText = ""
        viewModel.clearFloatingDrag()
        recoverFirstContentClick = true

        // Remember who was front so hide() can give focus back without NSApp.hide
        // (hide→unhide is what made the first content click a permanent no-op).
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            appToReactivate = front
        }

        let prefs = (try? preferencesStore.load()) ?? .default
        Localizer.setLanguage(prefs.language)
        viewModel.showSystemApplications = prefs.showSystemApplications
        viewModel.showHiddenInSearch = prefs.showHiddenInSearch
        DiagLog.write("show() pid=\(ProcessInfo.processInfo.processIdentifier) bundle=\(Bundle.main.bundlePath) loaded prefs: showSystemApps=\(prefs.showSystemApplications) showHidden=\(prefs.showHiddenInSearch)")

        // Root container: hosting view (full) + AppKit search on top.
        // FirstMouseView: first click after NSApp.unhide must reach the grid
        // (otherwise every first tap — app / folder / blank dismiss — is a no-op).
        let container = FirstMouseView(frame: NSRect(origin: .zero, size: frame.size))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor

        let hosting = FirstMouseHostingView(rootView: ContentView(
            scrollModel: scrollModel,
            viewModel: viewModel,
            preferences: prefs
        ))
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        self.hostingView = hosting

        searchChrome.install(on: container) { [weak self] text in
            self?.viewModel.searchText = text
        }
        searchChrome.setText("")

        window.contentView = container
        window.setFrame(frame, display: true)
        self.window = window

        installScrollMonitor()
        installClickMonitor(window: window)
        installKeyMonitor(window: window)

        // Hotkey path: Carbon delivers the toggle while another app is frontmost.
        // Must unhide + activate + makeKey or local key monitors never fire and
        // typing never reaches the search field.
        activateForKeyboard(window)
    }

    /// Bring the overlay (and the app) to the front so keyboard events work.
    /// Dock clicks do this implicitly; Carbon hotkeys fire while another app is
    /// frontmost, so we re-assert activation + key status (without mutating
    /// collectionBehavior — incompatible flags crash in _validateCollectionBehavior).
    private func activateForKeyboard(_ window: NSWindow) {
        // Prefer not to rely on unhide — we no longer NSApp.hide on dismiss.
        if NSApp.isHidden {
            NSApp.unhide(nil)
        }
        NSApp.setActivationPolicy(.regular)
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        // Prefer the SwiftUI host as first responder so the first click is not
        // eaten as “activate contentView only”.
        if let hosting = hostingView {
            window.makeFirstResponder(hosting)
        } else if window.firstResponder == nil || window.firstResponder === window {
            window.makeFirstResponder(window.contentView)
        }
        installKeyMonitor(window: window)

        // Carbon hotkey can bounce focus back; re-assert once on next turn.
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, self.window === window, window.isVisible else { return }
            if #available(macOS 14.0, *) {
                NSApp.activate()
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }
            window.makeKeyAndOrderFront(nil)
            if !(window.firstResponder is NSTextField || window.firstResponder is NSTextView) {
                if let hosting = self.hostingView {
                    window.makeFirstResponder(hosting)
                } else {
                    window.makeFirstResponder(window.contentView)
                }
            }
            // Diagnostic for reports of an overlay that renders but takes no
            // input (unresponsive to click/Esc/scroll) right after macOS
            // relaunches the app for a permission change: if isActive/isKey
            // come back false here, the window is only *visually* frontmost
            // (high window level) while keyboard/mouse events are still being
            // routed to whatever app the system considers actually active —
            // NSApp.activate() can silently no-op in that relaunch context.
            DiagLog.write(
                "activate: isActive=\(NSApp.isActive) isKey=\(window.isKeyWindow) policy=\(NSApp.activationPolicy().rawValue) firstResponder=\(String(describing: type(of: window.firstResponder)))"
            )
        }
    }

    func hide() {
        removeScrollMonitor()
        removeClickMonitor()
        removeKeyMonitor()
        removeFloatingDragMonitor()
        removeFloatingGhost()
        searchChrome.remove()
        hostingView = nil
        window?.orderOut(nil)
        window = nil
        recoverFirstContentClick = false

        // Do NOT NSApp.hide — the matching unhide makes the next show()'s first
        // click a no-op for SwiftUI (app/folder/blank all need a second click).
        // Hand focus back to whoever was frontmost before we opened.
        if let previous = appToReactivate, !previous.isTerminated {
            previous.activate()
        }
        appToReactivate = nil
    }

    // MARK: - Scroll

    private func installScrollMonitor() {
        removeScrollMonitor()
        var lastFlip = Date.distantPast
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let hijacks = MainActor.assumeIsolated { self?.scrollModel.hijacksScrollWheel ?? false }
            guard hijacks else { return event }
            let now = Date()
            guard now.timeIntervalSince(lastFlip) > 0.3 else { return nil }
            let deltaY = event.scrollingDeltaY
            let deltaX = event.scrollingDeltaX
            let delta = abs(deltaY) >= abs(deltaX) ? deltaY : deltaX
            guard abs(delta) > 0.5 else { return nil }
            let direction = delta < 0 ? 1 : -1
            NotificationCenter.default.post(name: .iLaunchPageScroll, object: direction)
            lastFlip = now
            return nil
        }
    }

    private func removeScrollMonitor() {
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
            scrollMonitor = nil
        }
    }

    // MARK: - Click (jiggle cancel on first blank click)

    private func installClickMonitor(window: NSWindow) {
        removeClickMonitor()
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self else { return event }
            // Local monitors fire on the main thread.
            return self.handleMouseDown(event)
        }
    }

    private func handleMouseDown(_ event: NSEvent) -> NSEvent? {
        guard let eventWindow = event.window, eventWindow is OverlayWindow else {
            return event
        }

        // Floating drag owns the pointer (app or folder handoff / drag-out).
        if viewModel.floatingDragItemID != nil {
            return event
        }

        // Clicks on the AppKit search field pass through.
        if hitSearchField(event) {
            recoverFirstContentClick = false
            return event
        }

        // Blank click while jiggling: cancel edit mode and consume.
        // Clicks **on a tile** must pass through so the first drag after
        // long-press jiggle can start (consuming every mouseDown forced a
        // second attempt before drag worked).
        if viewModel.editMode {
            recoverFirstContentClick = false
            if hitTile(event) {
                return event
            }
            viewModel.editMode = false
            NotificationCenter.default.post(name: .iLaunchEditModeCancelled, object: nil)
            return nil
        }

        // Folder popup: clicks inside the panel (member tap, reorder, drag-out)
        // must reach SwiftUI. Clicks outside it (blank backdrop) dismiss here
        // directly and are consumed — SwiftUI's onTapGesture on a large,
        // mostly-blank view proved unreliable on macOS, sometimes needing a
        // dozen-plus clicks before registering (reported: the gap between the
        // folder panel and the search box above it, though the failure isn't
        // actually position-specific — see the folder-tile-dismiss-click
        // investigation for the elimination process).
        if viewModel.openFolder != nil {
            recoverFirstContentClick = false
            if let window {
                let point = swiftUIPoint(fromWindow: event.locationInWindow, in: window)
                let panel = viewModel.folderPanelFrame
                let insidePanel = panel.width > 1 && panel.height > 1 && panel.contains(point)
                if !insidePanel {
                    // Scale-out runs inside FolderPopupView; do not nil immediately.
                    viewModel.requestCloseFolder()
                    return nil
                }
            }
            return event
        }

        // Searching: blank click (outside the search field) exits fullscreen.
        // Handled here because ScrollView often swallows SwiftUI blank taps.
        // A click on a result tile must pass through so SwiftUI's onLaunch
        // fires — otherwise every result tap silently dismissed the overlay
        // without opening the app.
        let searching = !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if searching {
            recoverFirstContentClick = false
            if hitTile(event) {
                return event
            }
            hide()
            return nil
        }

        // First click after show(): SwiftUI often never sees this mouseDown
        // (activation / first-mouse). Handle open-app / open-folder / blank
        // dismiss here and consume the event so the action still happens once.
        if recoverFirstContentClick {
            recoverFirstContentClick = false
            if performFirstContentClick(event) {
                return nil
            }
            // Unknown target — still pass through in case SwiftUI can use it.
        }

        // Defocus search if it somehow held focus while empty — but do NOT blur
        // on the same mouseDown that should activate a tile. Resigning first
        // responder mid-event drops the first grid/folder tap after show()
        // (only the second click worked). Blur on mouseUp instead.
        if eventWindow.firstResponder is NSTextView || eventWindow.firstResponder is NSTextField {
            DispatchQueue.main.async { [weak self] in
                self?.searchChrome.blur()
            }
        }
        return event
    }

    /// AppKit fallback for the first grid interaction after show().
    /// Returns true when the click was fully handled (caller should consume event).
    private func performFirstContentClick(_ event: NSEvent) -> Bool {
        guard let window else { return false }
        let point = swiftUIPoint(fromWindow: event.locationInWindow, in: window)

        // Smallest containing tile wins (tighter hit among overlapping frames).
        let hits = viewModel.tileFrames.filter {
            $0.frame.insetBy(dx: -6, dy: -6).contains(point)
        }
        let hit = hits.min {
            ($0.frame.width * $0.frame.height) < ($1.frame.width * $1.frame.height)
        }

        if let hit {
            if hit.isFolder {
                if let item = viewModel.gridDisplayItem(id: hit.id) {
                    DiagLog.write("firstClick recovery: open folder id=\(hit.id)")
                    viewModel.openFolderPopup(item)
                    return true
                }
            } else if let record = viewModel.appRecord(id: hit.id) {
                DiagLog.write("firstClick recovery: launch app id=\(hit.id)")
                viewModel.finishClosingFolder()
                NotificationCenter.default.post(name: .iLaunchDismiss, object: nil)
                DispatchQueue.main.async {
                    _ = AppLauncher().launch(record)
                }
                return true
            }
        }

        // Blank area → dismiss overlay (same as SwiftUI blank tap).
        DiagLog.write("firstClick recovery: blank dismiss at \(point)")
        hide()
        return true
    }

    private func hitSearchField(_ event: NSEvent) -> Bool {
        guard let content = window?.contentView else { return false }
        let p = content.convert(event.locationInWindow, from: nil)
        return searchChrome.view.frame.contains(p)
    }

    /// Whether the click lands on a grid tile (or folder member) frame so
    /// edit-mode drag / activate can receive the event.
    private func hitTile(_ event: NSEvent) -> Bool {
        guard let window else { return false }
        let point = swiftUIPoint(fromWindow: event.locationInWindow, in: window)
        // Slight inset slop so near-edge icon clicks still count as tile hits.
        return viewModel.tileFrames.contains { info in
            info.frame.insetBy(dx: -6, dy: -6).contains(point)
        }
    }

    private func removeClickMonitor() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
    }

    // MARK: - Floating drag (AppKit ghost — no SwiftUI coordinate flip bugs)

    private func installFloatingDragMonitor(appID: String?) {
        removeFloatingDragMonitor()
        // `appID` is a grid item id: app record id **or** folder id.
        guard let itemID = appID, let window else { return }

        // Build AppKit ghost at current mouse position (window coords, bottom-left).
        showFloatingGhost(for: itemID, at: window.mouseLocationOutsideOfEventStream)

        // Grid handoff often happens while the pointer is still in the edge zone
        // after one page flip — disarm until the finger leaves the edge so we
        // never flip a second page immediately.
        lastFloatingPageFlip = Date()
        floatingEdgeArmed = false

        floatingDragMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            guard let self else { return event }
            return self.handleFloatingDrag(event, itemID: itemID)
        }
    }

    private func handleFloatingDrag(_ event: NSEvent, itemID: String) -> NSEvent? {
        guard let window else { return event }
        let windowPoint = event.locationInWindow

        if event.type == .leftMouseDragged {
            moveFloatingGhost(to: windowPoint)
            // Sync pointer + drive grid live gap / folder-create sensing so
            // drag-out (and edge page-flip handoff) match main-grid feedback.
            let point = swiftUIPoint(fromWindow: windowPoint, in: window)
            self.maybeFlipPageDuringFloatingDrag(windowPoint: windowPoint, window: window)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                self.viewModel.updateFloatingDrag(at: point)
            }
            return nil
        }

        if event.type == .leftMouseUp {
            let point = swiftUIPoint(fromWindow: windowPoint, in: window)
            viewModel.resolveDrop(
                sourceID: itemID,
                at: point,
                page: viewModel.currentPage
            )
            removeFloatingGhost()
            removeFloatingDragMonitor()
            NotificationCenter.default.post(name: .iLaunchEditDragEnded, object: nil)
            NotificationCenter.default.post(name: .iLaunchGridDragEnded, object: nil)
            return nil
        }
        return event
    }

    private func showFloatingGhost(for itemID: String, at windowPoint: NSPoint) {
        removeFloatingGhost()
        guard let window, let content = window.contentView else { return }

        let size: CGFloat = 96
        let container = NSView(frame: NSRect(x: 0, y: 0, width: size, height: size + 28))
        container.wantsLayer = true
        container.layer?.zPosition = 10_000

        let title: String
        if let record = viewModel.appRecord(id: itemID) {
            let icon = NSImageView(frame: NSRect(x: 0, y: 28, width: size, height: size))
            icon.imageScaling = .scaleProportionallyUpOrDown
            icon.image = NSWorkspace.shared.icon(forFile: record.path)
            container.addSubview(icon)
            title = record.name
            viewModel.floatingDragApp = record
        } else if let display = viewModel.gridDisplayItem(id: itemID) {
            // Folder ghost must look like FolderTileView (3×3 member preview),
            // not a system folder.fill symbol.
            let tileHost = NSHostingView(rootView: FolderTileView(members: display.members, size: size))
            tileHost.frame = NSRect(x: 0, y: 28, width: size, height: size)
            tileHost.wantsLayer = true
            tileHost.layer?.backgroundColor = NSColor.clear.cgColor
            tileHost.layer?.isOpaque = false
            container.addSubview(tileHost)
            title = display.title
            viewModel.floatingDragApp = nil
        } else {
            return
        }

        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = .white
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.frame = NSRect(x: -10, y: 0, width: size + 20, height: 24)
        container.addSubview(label)

        // Always above SwiftUI hosting content and search chrome.
        content.addSubview(container, positioned: .above, relativeTo: nil)
        floatingGhostView = container
        viewModel.floatingDragItemID = itemID
        moveFloatingGhost(to: windowPoint)
    }

    private func moveFloatingGhost(to windowPoint: NSPoint) {
        guard let ghost = floatingGhostView else { return }
        let size = ghost.frame.size
        ghost.frame.origin = NSPoint(
            x: windowPoint.x - size.width / 2,
            y: windowPoint.y - size.height / 2
        )
        // Re-assert topmost in case hosting view re-layered.
        ghost.superview?.addSubview(ghost, positioned: .above, relativeTo: nil)
    }

    private func removeFloatingGhost() {
        floatingGhostView?.removeFromSuperview()
        floatingGhostView = nil
    }

    private func removeFloatingDragMonitor() {
        if let monitor = floatingDragMonitor {
            NSEvent.removeMonitor(monitor)
            floatingDragMonitor = nil
        }
    }

    /// Edge page-flip while AppKit floating drag is active (grid handoff or
    /// folder drag-out). One page per edge visit: leave the zone to re-arm.
    private var lastFloatingPageFlip = Date.distantPast
    private var floatingEdgeArmed = true
    private func maybeFlipPageDuringFloatingDrag(windowPoint: NSPoint, window: NSWindow) {
        let bounds = window.contentView?.bounds ?? window.frame
        let edgeZone: CGFloat = 56
        let inLeft = windowPoint.x < edgeZone
        let inRight = windowPoint.x > bounds.width - edgeZone

        if !inLeft && !inRight {
            floatingEdgeArmed = true
            return
        }
        guard floatingEdgeArmed else { return }

        let now = Date()
        guard now.timeIntervalSince(lastFloatingPageFlip) > 0.75 else { return }
        let pageCount = max(1, viewModel.visiblePages.count)
        if inLeft, viewModel.currentPage > 0 {
            viewModel.currentPage -= 1
            lastFloatingPageFlip = now
            floatingEdgeArmed = false
            NotificationCenter.default.post(
                name: .iLaunchGoToPage,
                object: viewModel.currentPage
            )
        } else if inRight, viewModel.currentPage < pageCount - 1 {
            viewModel.currentPage += 1
            lastFloatingPageFlip = now
            floatingEdgeArmed = false
            NotificationCenter.default.post(
                name: .iLaunchGoToPage,
                object: viewModel.currentPage
            )
        }
    }

    /// Window (AppKit, origin bottom-left) → SwiftUI overlay (origin top-left).
    /// Always convert through the `NSHostingView` so the point matches
    /// `TileFramePreferenceKey` / `.named("overlay")` coordinates.
    private func swiftUIPoint(fromWindow windowPoint: NSPoint, in window: NSWindow) -> CGPoint {
        if let hosting = hostingView {
            let p = hosting.convert(windowPoint, from: nil)
            if hosting.isFlipped {
                return CGPoint(x: p.x, y: p.y)
            }
            return CGPoint(x: p.x, y: hosting.bounds.height - p.y)
        }
        guard let content = window.contentView else {
            return CGPoint(x: windowPoint.x, y: windowPoint.y)
        }
        let p = content.convert(windowPoint, from: nil)
        if content.isFlipped {
            return CGPoint(x: p.x, y: p.y)
        }
        return CGPoint(x: p.x, y: content.bounds.height - p.y)
    }

    // MARK: - Key

    private func installKeyMonitor(window: NSWindow) {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            // Overlay must be up. Do NOT require event.window == OverlayWindow:
            // after a Carbon hotkey, the first keys often arrive with window==nil
            // until the window fully becomes key — those must still start search.
            guard let overlay = self.window, overlay.isVisible else { return event }
            if let ew = event.window, !(ew is OverlayWindow), ew !== overlay {
                return event
            }

            // Esc → leave overlay (works even when NSTextField has focus;
            // SwiftUI onExitCommand does not fire for AppKit first responders).
            if event.keyCode == 53 { // kVK_Escape
                self.handleEscape()
                return nil
            }

            // Already typing in the search field / field editor — pass through
            // so multi-char input and Chinese IME keep working.
            if let fr = overlay.firstResponder ?? event.window?.firstResponder,
               fr is NSTextView || fr is NSTextField {
                return event
            }

            // Printable character → focus search and feed the key (IME-safe).
            guard let chars = event.charactersIgnoringModifiers,
                  let first = chars.unicodeScalars.first,
                  first.value >= 32, first.value != 127,
                  !event.modifierFlags.contains(.command),
                  !event.modifierFlags.contains(.control)
            else {
                return event
            }

            // Ensure we are key, then focus + interpret so the first keystroke
            // is not lost (and Chinese IME still works via interpretKeyEvents).
            overlay.makeKeyAndOrderFront(nil)
            self.searchChrome.interpretKeyEvent(event)
            return nil
        }
    }

    private func handleEscape() {
        if viewModel.editMode {
            viewModel.editMode = false
            NotificationCenter.default.post(name: .iLaunchEditModeCancelled, object: nil)
            return
        }
        if viewModel.openFolder != nil {
            viewModel.requestCloseFolder()
            return
        }
        // Searching or idle → leave fullscreen.
        hide()
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }
}
