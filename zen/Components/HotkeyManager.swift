import Cocoa
import Carbon
import Combine

/// Registers the user's recording shortcut as a global Carbon hotkey. This
/// is the only place hotkey presses are debounced.
@MainActor
final class HotkeyManager: ObservableObject {
    static let shared = HotkeyManager()

    var onToggle: (() -> Void)?

    /// Set when the saved shortcut couldn't be registered at launch, e.g.
    /// because another app already owns it.
    @Published private(set) var registrationError: String?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var localMonitor: Any?
    nonisolated private static let signature: OSType = 0x5A454E21 // "ZEN!"
    nonisolated private static let hotKeyID: UInt32 = 1
    private var lastTriggerUptime: TimeInterval = 0
    private var isActive = false
    private var suspensionCount = 0
    private let state = ZenState.shared

    private init() {}

    func triggerToggle() {
        let now = ProcessInfo.processInfo.systemUptime
        // Debounce by 350ms to absorb key repeat and a press seen by both
        // the Carbon hotkey and the local monitor.
        guard now - lastTriggerUptime > 0.35 else { return }
        lastTriggerUptime = now
        print("[Hotkey] Triggering hotkey toggle")
        onToggle?()
    }

    /// Start listening for the saved shortcut. Called once onboarding is done.
    func activate() {
        isActive = true
        installHandlers()
        if let error = registerHotKey(state.recordingShortcut) {
            registrationError = error
        }
    }

    /// Validates, registers and saves a new shortcut. On failure the previous
    /// shortcut stays registered and saved, and the reason is returned.
    func setShortcut(_ shortcut: RecordingShortcut) -> String? {
        if let error = shortcut.validationError { return error }
        let previous = state.recordingShortcut
        if isActive {
            if let error = registerHotKey(shortcut) {
                if suspensionCount == 0 { _ = registerHotKey(previous) }
                return error
            }
            // A recorder that's still listening re-registers on resume().
            if suspensionCount > 0 { unregisterHotKey() }
        }
        state.recordingShortcut = shortcut
        registrationError = nil
        return nil
    }

    /// Pause the hotkey while a shortcut recorder listens, so pressing the
    /// current shortcut doesn't start a recording. Balance with `resume()`.
    func suspend() {
        suspensionCount += 1
        if suspensionCount == 1 { unregisterHotKey() }
    }

    func resume() {
        guard suspensionCount > 0 else { return }
        suspensionCount -= 1
        guard suspensionCount == 0, isActive else { return }
        registrationError = registerHotKey(state.recordingShortcut)
    }

    private func installHandlers() {
        guard eventHandlerRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

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
                DispatchQueue.main.async {
                    HotkeyManager.shared.triggerToggle()
                }
            }
            return noErr
        }

        let installStatus = InstallEventHandler(
            GetEventDispatcherTarget(), handler, 1, &eventType, nil, &eventHandlerRef
        )
        if installStatus != noErr {
            print("[Hotkey] Failed to install event handler (error \(installStatus))")
        }

        // Fallback for when Zen itself is active and focused.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.hotKeyRef != nil, self.state.recordingShortcut.matches(event) else { return event }
            self.triggerToggle()
            return nil
        }
    }

    /// Replaces any registered hotkey. Returns a user-facing error on failure.
    private func registerHotKey(_ shortcut: RecordingShortcut) -> String? {
        unregisterHotKey()
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
            print("[Hotkey] Failed to register \(shortcut.spokenDescription) (error \(status))")
            return status == eventHotKeyExistsErr
                ? "\(shortcut.displayString) is already in use by another app."
                : "Couldn’t register \(shortcut.displayString) (error \(status))."
        }
        print("[Hotkey] Registered \(shortcut.spokenDescription) as global hotkey")
        return nil
    }

    private func unregisterHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }
}
