import os
import AppKit
import Carbon.HIToolbox
import Combine

/// Listens for a new recording shortcut. There is one capture at a time,
/// shared by Settings and onboarding, so the onboarding heading can show keys
/// as they are pressed. While listening, the global hotkey is paused so
/// pressing the current shortcut doesn't start a recording.
@MainActor
final class ShortcutCapture: ObservableObject {
    static let shared = ShortcutCapture()

    @Published private(set) var isCapturing = false
    @Published private(set) var heldModifiers: NSEvent.ModifierFlags = []
    @Published var message: String?

    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []
    /// The one modifier key held so far with nothing else, which becomes a
    /// single-key shortcut if it's released that way.
    private var soloModifier: UInt16?
    private var heldWithFunction: NSEvent.ModifierFlags = []

    private init() {}

    /// Symbols for the modifiers currently held, e.g. "⌃⌥".
    var heldSymbols: String { RecordingShortcut(keyCode: 0, flags: heldModifiers).modifierSymbols }

    func toggle() { isCapturing ? stop() : start() }

    func start() {
        guard !isCapturing else { return }
        isCapturing = true
        message = nil
        heldModifiers = []
        heldWithFunction = []
        soloModifier = nil
        HotkeyManager.shared.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.isCapturing else { return event }
            self.handle(event)
            return nil
        }
        // Stop as soon as focus leaves, so the global shortcut is never left
        // paused: Settings windows are hidden rather than destroyed, so the
        // view's own disappearance can't be relied on.
        let center = NotificationCenter.default
        var names: [(Notification.Name, Any?)] = [(NSApplication.didResignActiveNotification, nil)]
        if let window = NSApp.keyWindow {
            names += [(NSWindow.didResignKeyNotification, window), (NSWindow.willCloseNotification, window)]
        }
        observers = names.map { name, object in
            center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.stop() }
            }
        }
        Log.hotkey.notice("Shortcut capture started (key window: \(NSApp.keyWindow?.title ?? "none", privacy: .public))")
    }

    func stop() {
        guard isCapturing else { return }
        isCapturing = false
        heldModifiers = []
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        HotkeyManager.shared.resume()
        Log.hotkey.notice("Shortcut capture stopped")
    }

    func handle(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])
        if event.type == .flagsChanged {
            let held = event.modifierFlags.intersection([.control, .option, .shift, .command, .function])
            if RecordingShortcut.isModifierKeyDown(event.keyCode, flags: event.modifierFlags) {
                // Only a modifier pressed while nothing else is held can stand on its own.
                soloModifier = heldWithFunction.isEmpty ? event.keyCode : nil
            } else if held.isEmpty, let key = soloModifier {
                soloModifier = nil
                heldWithFunction = []
                heldModifiers = []
                apply(RecordingShortcut(keyCode: UInt32(key), modifiers: 0))
                return
            }
            heldWithFunction = held
            heldModifiers = flags
            return
        }
        guard event.type == .keyDown, !event.isARepeat else { return }
        soloModifier = nil
        if event.keyCode == UInt16(kVK_Escape) && flags.isEmpty {
            message = nil
            stop()
            return
        }
        apply(RecordingShortcut(keyCode: event.keyCode, flags: flags))
    }

    private func apply(_ shortcut: RecordingShortcut) {
        Log.hotkey.notice("Shortcut capture received \(shortcut.spokenDescription, privacy: .public)")
        if let error = HotkeyManager.shared.setShortcut(shortcut) {
            message = error // Keep listening so another combination can be tried.
            Log.hotkey.notice("Shortcut rejected: \(error, privacy: .public)")
        } else {
            message = nil
            stop()
        }
    }
}
