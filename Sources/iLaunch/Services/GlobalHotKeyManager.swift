import AppKit
import Carbon

/// Registers a system-wide hot key using the
/// Carbon RegisterEventHotKey API, which works globally WITHOUT requiring
/// accessibility permission — unlike NSEvent.addGlobalMonitorForEvents.
final class GlobalHotKeyManager: @unchecked Sendable {
    private let onToggle: () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var currentKeyCode: UInt32 = UInt32(kVK_Space)
    private var currentModifiers: UInt32 = UInt32(optionKey)
    private var nextHotKeyID: UInt32 = 1
    private let f4Mapping = F4KeyMapping()
    private(set) var usesFnF4 = false

    init(onToggle: @escaping () -> Void) {
        self.onToggle = onToggle
    }

    /// Installs the Carbon event handler (once) and registers the initial
    /// hotkey. Call once at launch with the user's stored preference.
    func start(keyCode: UInt32, modifiers: UInt32) {
        installEventHandlerIfNeeded()
        currentKeyCode = keyCode
        currentModifiers = modifiers
        if register(keyCode: keyCode, modifiers: modifiers) { return }
        DiagLog.write("GlobalHotKeyManager.start: failed to register initial hotkey (code=\(keyCode) mods=\(modifiers))")
        // Fall back to the Option+Space default so the app never launches
        // with zero working hotkey.
        let fallbackKeyCode = UInt32(kVK_Space)
        let fallbackModifiers = UInt32(optionKey)
        currentKeyCode = fallbackKeyCode
        currentModifiers = fallbackModifiers
        if !register(keyCode: fallbackKeyCode, modifiers: fallbackModifiers) {
            DiagLog.write("GlobalHotKeyManager.start: fallback Option+Space registration also failed — no hotkey is currently active")
        }
    }

    /// Unregisters the current hotkey and registers `keyCode`/`modifiers`.
    /// Returns `false` (and leaves the previous hotkey active) if the new
    /// combo is already registered by another app — the Carbon
    /// `RegisterEventHotKey` error is the only conflict signal available;
    /// there's no API to enumerate who holds a combo.
    @discardableResult
    func updateHotKey(keyCode: UInt32, modifiers: UInt32, refreshF4: Bool = false) -> Bool {
        let previousKeyCode = currentKeyCode
        let previousModifiers = currentModifiers
        unregisterCurrent()
        if register(keyCode: keyCode, modifiers: modifiers, refreshF4: refreshF4) {
            currentKeyCode = keyCode
            currentModifiers = modifiers
            if keyCode != UInt32(kVK_F4) || modifiers != 0 {
                f4Mapping.restore()
                usesFnF4 = false
            }
            return true
        }
        // Roll back so the overlay toggle keeps working.
        if register(keyCode: previousKeyCode, modifiers: previousModifiers) {
            currentKeyCode = previousKeyCode
            currentModifiers = previousModifiers
        } else {
            DiagLog.write("GlobalHotKeyManager.updateHotKey: rollback registration also failed — no hotkey is currently active")
        }
        return false
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                // Hop to main; overlay activation must not race Carbon's own
                // event unwind (that was stealing key focus back).
                DispatchQueue.main.async {
                    manager.onToggle()
                }
                return noErr
            },
            1, &eventType, selfPtr, &eventHandlerRef
        )
    }

    /// Registers `keyCode`/`modifiers` under a fresh hotkey ID. Returns
    /// whether registration succeeded.
    @discardableResult
    private func register(keyCode: UInt32, modifiers: UInt32, refreshF4: Bool = false) -> Bool {
        if keyCode == UInt32(kVK_F4), modifiers == 0 {
            if refreshF4 {
                let standard = F4KeyMapping.standardFunctionKeys
                let selectedCode = standard ? UInt32(kVK_F20) : keyCode
                guard registerCarbon(keyCode: selectedCode, modifiers: 0) else { return false }
                guard f4Mapping.apply(standardFunctionKeys: standard, refresh: true) else {
                    unregisterCurrent()
                    return false
                }
                usesFnF4 = standard
                return true
            }
            if usesFnF4 { return registerCarbon(keyCode: UInt32(kVK_F20), modifiers: 0) }
            let standard = F4KeyMapping.standardFunctionKeys
            if standard, registerCarbon(keyCode: UInt32(kVK_F20), modifiers: 0) {
                if f4Mapping.apply(standardFunctionKeys: true) {
                    usesFnF4 = true
                    return true
                }
                unregisterCurrent()
            }
            guard registerCarbon(keyCode: keyCode, modifiers: modifiers) else { return false }
            if !standard { _ = f4Mapping.apply(standardFunctionKeys: false) }
            return true
        }
        return registerCarbon(keyCode: keyCode, modifiers: modifiers)
    }

    private func registerCarbon(keyCode: UInt32, modifiers: UInt32) -> Bool {
        nextHotKeyID += 1
        let hotKeyID = EventHotKeyID(signature: 0x494E4350, id: nextHotKeyID) // "INCP"
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else { return false }
        hotKeyRef = ref
        return true
    }

    private func unregisterCurrent() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    func stop() {
        unregisterCurrent()
        f4Mapping.restore()
        usesFnF4 = false
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
    }

    /// Returns true if the app has accessibility permission.
    static var hasAccessibility: Bool {
        AXIsProcessTrusted()
    }

    /// Prompt the user to grant accessibility permission. Opens System Settings.
    @MainActor
    static func requestAccessibility() {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let options = [key: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    deinit {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
        if let handler = eventHandlerRef { RemoveEventHandler(handler) }
    }
}
