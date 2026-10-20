import AppKit
import Carbon.HIToolbox

/// Shortcut capture driven by real key events through the app's event queue,
/// the path the Settings and onboarding recorders use. Briefly registers a
/// global hotkey in this process, so run it with Zen quit or expect Zen's
/// shortcut to be busy for a second.
final class KeyPanel: NSPanel { override var canBecomeKey: Bool { true } }

@main
@MainActor
struct ShortcutCaptureChecks {
    static func key(_ type: NSEvent.EventType, _ code: Int, _ flags: NSEvent.ModifierFlags, window: NSWindow) {
        NSApp.postEvent(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: UInt16(code))!, atStart: false)
    }
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let state = ZenState.shared
        state.recordingShortcut = .default
        HotkeyManager.shared.activate()
        let window = KeyPanel(contentRect: CGRect(x: -3000, y: -3000, width: 300, height: 100), styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        window.makeKeyAndOrderFront(nil)
        var failures = 0
        func check(_ ok: Bool, _ label: String) { print(ok ? "PASS" : "FAIL", label); if !ok { failures += 1 } }
        _ = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            let capture = ShortcutCapture.shared

            // 1. Choose Control+Option+D.
            capture.start()
            check(capture.isCapturing, "capture starts")
            key(.flagsChanged, kVK_Control, [.control, .option], window: window)
            try? await Task.sleep(for: .milliseconds(200))
            check(capture.heldSymbols == "⌃⌥", "held modifiers shown live (\(capture.heldSymbols))")
            key(.keyDown, kVK_ANSI_D, [.control, .option], window: window)
            try? await Task.sleep(for: .milliseconds(200))
            let chosen = RecordingShortcut(keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(controlKey | optionKey))
            check(state.recordingShortcut == chosen, "new shortcut saved (\(state.recordingShortcut.displayString))")
            check(!capture.isCapturing, "capture ends after a valid shortcut")

            // 2. A reserved shortcut is rejected and listening continues.
            capture.start()
            key(.keyDown, kVK_ANSI_V, [.command], window: window)
            try? await Task.sleep(for: .milliseconds(200))
            check(capture.isCapturing && capture.message != nil, "reserved ⌘V rejected, still listening")
            check(state.recordingShortcut == chosen, "rejected shortcut not saved")

            // 3. Focus loss stops the capture and restores the hotkey.
            NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
            try? await Task.sleep(for: .milliseconds(100))
            check(!capture.isCapturing, "focus loss stops capture")

            // 4. Escape cancels without changing anything.
            capture.start()
            key(.keyDown, kVK_Escape, [], window: window)
            try? await Task.sleep(for: .milliseconds(200))
            check(!capture.isCapturing && state.recordingShortcut == chosen, "Escape cancels")

            // 5. A right-side modifier pressed and released alone becomes the shortcut.
            let rightControlDown = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.control.rawValue | 0x2000)
            capture.start()
            key(.flagsChanged, kVK_RightControl, rightControlDown, window: window)
            key(.flagsChanged, kVK_RightControl, [], window: window)
            try? await Task.sleep(for: .milliseconds(200))
            check(state.recordingShortcut == RecordingShortcut(keyCode: UInt32(kVK_RightControl), modifiers: 0)
                  && !capture.isCapturing, "Right Control alone saved (\(state.recordingShortcut.displayString))")

            // 6. Left Control alone is rejected; Right Control with a key is a combination.
            capture.start()
            key(.flagsChanged, kVK_Control, NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.control.rawValue | 0x0001), window: window)
            key(.flagsChanged, kVK_Control, [], window: window)
            try? await Task.sleep(for: .milliseconds(200))
            check(capture.isCapturing && capture.message != nil, "Left Control alone rejected, still listening")
            key(.flagsChanged, kVK_RightControl, rightControlDown, window: window)
            key(.keyDown, kVK_ANSI_D, rightControlDown, window: window)
            try? await Task.sleep(for: .milliseconds(200))
            check(state.recordingShortcut == RecordingShortcut(keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(controlKey)),
                  "Right Control + D saved as a combination (\(state.recordingShortcut.displayString))")

            state.recordingShortcut = .default
            exit(failures == 0 ? 0 : 1)
        }
        app.run()
    }
}
