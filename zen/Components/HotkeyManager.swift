import os
import Cocoa
import Carbon
import Combine

/// Watches the user's recording shortcut and reports when it goes down and
/// comes back up; `PillPanelManager` turns those into hold-to-talk and
/// hands-free recording.
///
/// Key combinations are global Carbon hotkeys, which need no permission. A
/// single modifier key such as Right Control can't be a Carbon hotkey, so it's
/// read from key events instead, which needs Accessibility access outside Zen.
@MainActor
final class HotkeyManager: ObservableObject {
    static let shared = HotkeyManager()

    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    /// A single-key shortcut became part of another shortcut, like Right
    /// Control + C, so whatever its press started should be dropped.
    var onInterrupt: (() -> Void)?

    /// Why the shortcut doesn't work everywhere: it couldn't be registered at
    /// launch, or a single-key shortcut is waiting for Accessibility access.
    @Published private(set) var registrationError: String?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var trustTimer: Timer?
    nonisolated private static let signature: OSType = 0x5A454E21 // "ZEN!"
    nonisolated private static let hotKeyID: UInt32 = 1
    private var isActive = false
    private var isListening = false
    private var isDown = false
    private var isInterrupted = false
    private var suspensionCount = 0
    private let state = ZenState.shared

    private init() {}

    /// Start listening for the saved shortcut. Called once onboarding is done.
    func activate() {
        isActive = true
        installHandlers()
        registrationError = register(state.recordingShortcut)
    }

    /// Validates, registers and saves a new shortcut. On failure the previous
    /// shortcut stays registered and saved, and the reason is returned.
    func setShortcut(_ shortcut: RecordingShortcut) -> String? {
        if let error = shortcut.validationError { return error }
        let previous = state.recordingShortcut
        if isActive {
            if let error = register(shortcut), !shortcut.isModifierOnly {
                if suspensionCount == 0 { _ = register(previous) }
                return error
            }
            // A recorder that's still listening re-registers on resume().
            if suspensionCount > 0 { unregister() }
        }
        state.recordingShortcut = shortcut
        registrationError = isActive ? accessibilityNote(for: shortcut) : nil
        return nil
    }

    /// Pause the shortcut while a recorder or onboarding listens for it, so
    /// pressing it doesn't start a recording. Balance with `resume()`.
    func suspend() {
        suspensionCount += 1
        if suspensionCount == 1 { unregister() }
    }

    func resume() {
        guard suspensionCount > 0 else { return }
        suspensionCount -= 1
        guard suspensionCount == 0, isActive else { return }
        registrationError = register(state.recordingShortcut)
    }

    // MARK: Press and release

    private func press() {
        guard !isDown else { return } // Key repeat, or Carbon and the local monitor both seeing it.
        isDown = true
        isInterrupted = false
        Log.hotkey.notice("Shortcut down")
        onPress?()
    }

    private func release() {
        guard isDown else { return }
        isDown = false
        if isInterrupted {
            isInterrupted = false
            return
        }
        Log.hotkey.notice("Shortcut up")
        onRelease?()
    }

    private func interrupt() {
        guard isDown, !isInterrupted else { return }
        isInterrupted = true
        Log.hotkey.notice("Shortcut used with another key; dropping its press")
        onInterrupt?()
    }

    /// Single-key shortcuts: its own key going down and up, and any other key
    /// joining in while it's held.
    private func handleModifierShortcut(_ event: NSEvent) {
        let shortcut = state.recordingShortcut
        switch event.type {
        case .flagsChanged where UInt32(event.keyCode) == shortcut.keyCode:
            RecordingShortcut.isModifierKeyDown(event.keyCode, flags: event.modifierFlags) ? press() : release()
        case .flagsChanged:
            if RecordingShortcut.isModifierKeyDown(event.keyCode, flags: event.modifierFlags) { interrupt() }
        case .keyDown:
            interrupt()
        default:
            break
        }
    }

    // MARK: Registration

    private func installHandlers() {
        guard eventHandlerRef == nil else { return }

        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]

        // Carbon hotkeys work across all applications without Accessibility
        // or Input Monitoring permission.
        let handler: EventHandlerUPP = { _, event, _ in
            guard let event else { return noErr }
            var hkID = EventHotKeyID()
            let err = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hkID
            )
            if err == noErr && hkID.signature == HotkeyManager.signature && hkID.id == HotkeyManager.hotKeyID {
                let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
                DispatchQueue.main.async {
                    pressed ? HotkeyManager.shared.press() : HotkeyManager.shared.release()
                }
            }
            return noErr
        }

        let installStatus = InstallEventHandler(
            GetEventDispatcherTarget(), handler, eventTypes.count, &eventTypes, nil, &eventHandlerRef
        )
        if installStatus != noErr {
            Log.hotkey.error("Failed to install the hotkey handler (error \(installStatus))")
        }

        // Carbon hotkeys don't fire while Zen itself is active, and single-key
        // shortcuts always come through here when Zen is.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard let self, self.isListening else { return event }
            let shortcut = self.state.recordingShortcut
            if shortcut.isModifierOnly {
                self.handleModifierShortcut(event)
                return event // Let the modifier reach whatever it's modifying.
            }
            switch event.type {
            case .keyDown where shortcut.matches(event):
                self.press()
                return nil
            case .keyUp where UInt32(event.keyCode) == shortcut.keyCode && self.isDown:
                self.release()
                return nil
            default:
                return event
            }
        }
    }

    /// Replaces whatever is registered. Returns a user-facing message when the
    /// shortcut can't work in every app.
    private func register(_ shortcut: RecordingShortcut) -> String? {
        unregister()
        if shortcut.isModifierOnly {
            isListening = true
            installGlobalMonitor()
            if !AXIsProcessTrusted() { waitForAccessibility() }
            Log.hotkey.notice("Listening for \(shortcut.spokenDescription, privacy: .public) as a single-key shortcut")
            return accessibilityNote(for: shortcut)
        }
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            EventHotKeyID(signature: Self.signature, id: Self.hotKeyID),
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        guard status == noErr else {
            hotKeyRef = nil
            Log.hotkey.error("Failed to register \(shortcut.spokenDescription, privacy: .public) (error \(status))")
            return status == eventHotKeyExistsErr
                ? "\(shortcut.displayString) is already in use by another app."
                : "Couldn’t register \(shortcut.displayString) (error \(status))."
        }
        isListening = true
        Log.hotkey.notice("Registered \(shortcut.spokenDescription, privacy: .public) as global hotkey")
        return nil
    }

    private func unregister() {
        trustTimer?.invalidate()
        trustTimer = nil
        isListening = false
        isDown = false
        isInterrupted = false
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        globalMonitor = nil
        if let hotKeyRef {
            Log.hotkey.notice("Unregistered global hotkey")
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    /// Key events from other apps only arrive once Zen has Accessibility access.
    private func installGlobalMonitor() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.handleModifierShortcut(event) }
        }
    }

    /// Accessibility can be granted while Zen is running. Monitors added
    /// before then never receive events, so add it again once it is.
    private func waitForAccessibility() {
        trustTimer?.invalidate()
        trustTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, AXIsProcessTrusted() else { return }
                timer.invalidate()
                self.trustTimer = nil
                guard self.isListening, self.state.recordingShortcut.isModifierOnly else { return }
                self.installGlobalMonitor()
                self.registrationError = nil
                Log.hotkey.notice("Accessibility granted; listening for the single-key shortcut in other apps")
            }
        }
    }

    private func accessibilityNote(for shortcut: RecordingShortcut) -> String? {
        guard shortcut.isModifierOnly, !AXIsProcessTrusted() else { return nil }
        return "\(shortcut.keyName) works in other apps once Zen has Accessibility access. Set it up below."
    }
}
