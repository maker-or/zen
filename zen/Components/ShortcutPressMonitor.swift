import AppKit
import Combine

/// Watches for the recording shortcut inside Zen's own windows, so onboarding
/// can show it working before Zen listens for it everywhere. While watching,
/// the global shortcut is paused so a replayed onboarding doesn't record.
@MainActor
final class ShortcutPressMonitor: ObservableObject {
    static let shared = ShortcutPressMonitor()

    @Published private(set) var isPressed = false
    /// The current shortcut has been pressed at least once.
    @Published private(set) var hasWorked = false

    private var monitor: Any?
    private var shortcutObserver: AnyCancellable?
    private let state = ZenState.shared

    private init() {}

    func start() {
        guard monitor == nil else { return }
        isPressed = false
        hasWorked = false
        HotkeyManager.shared.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            return MainActor.assumeIsolated { self.consumes(event) } ? nil : event
        }
        // A newly chosen shortcut hasn't been tried yet.
        shortcutObserver = state.$recordingShortcut.dropFirst().sink { [weak self] _ in
            self?.isPressed = false
            self?.hasWorked = false
        }
    }

    func stop() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
        shortcutObserver = nil
        isPressed = false
        HotkeyManager.shared.resume()
    }

    /// Whether the event was the shortcut being tried, kept from the window
    /// so ⌥ Space doesn't type a space or press a focused button.
    private func consumes(_ event: NSEvent) -> Bool {
        // A shortcut being chosen isn't one being tried.
        guard !ShortcutCapture.shared.isCapturing else {
            isPressed = false
            return false
        }
        let shortcut = state.recordingShortcut
        if shortcut.isModifierOnly {
            if event.type == .flagsChanged && UInt32(event.keyCode) == shortcut.keyCode {
                setPressed(RecordingShortcut.isModifierKeyDown(event.keyCode, flags: event.modifierFlags))
            } else if event.type == .keyDown {
                isPressed = false // Part of another shortcut, like Right Control + C.
            }
            return false // Let the modifier reach whatever it's modifying.
        }
        switch event.type {
        case .keyDown where shortcut.matches(event):
            if !event.isARepeat { setPressed(true) }
            return true
        case .keyUp where UInt32(event.keyCode) == shortcut.keyCode && isPressed:
            setPressed(false)
            return true
        default:
            return false
        }
    }

    private func setPressed(_ pressed: Bool) {
        isPressed = pressed
        if pressed { hasWorked = true }
    }
}
