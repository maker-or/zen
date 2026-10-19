import SwiftUI
import AppKit
import Carbon.HIToolbox

/// Click, then press a key combination to change the recording shortcut.
/// Escape cancels. While listening, the global hotkey is paused so pressing
/// the current shortcut doesn't start a recording.
struct ShortcutRecorder: View {
    enum Style { case settings, onboarding }

    var style: Style = .settings
    @ObservedObject private var state = ZenState.shared
    @State private var isRecording = false
    @State private var heldModifiers: NSEvent.ModifierFlags = []
    @State private var message: String?
    @State private var monitor: Any?

    var body: some View {
        VStack(alignment: style == .settings ? .trailing : .leading, spacing: 6) {
            switch style {
            case .settings: settingsControl
            case .onboarding: onboardingControl
            }
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(style == .settings ? AnyShapeStyle(.red) : AnyShapeStyle(OnboardingPalette.accent))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(style == .settings ? .trailing : .leading)
            }
        }
        .onDisappear(perform: stopRecording)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            stopRecording()
        }
    }

    private var settingsControl: some View {
        HStack(spacing: 8) {
            Button(action: toggleRecording) {
                Text(isRecording ? recordingPrompt : state.recordingShortcut.displayString)
                    .monospacedDigit()
                    .frame(minWidth: 110)
            }
            .help(isRecording ? "Press a new shortcut, or Esc to cancel" : "Click to change the shortcut")
            .accessibilityLabel(isRecording ? "Listening for a new shortcut"
                                : "Recording shortcut, \(state.recordingShortcut.spokenDescription)")
            .accessibilityHint("Press a key combination, or Escape to cancel")

            if state.recordingShortcut != .default && !isRecording {
                Button {
                    message = HotkeyManager.shared.setShortcut(.default)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .help("Reset to \(RecordingShortcut.default.displayString)")
                .accessibilityLabel("Reset to \(RecordingShortcut.default.spokenDescription)")
            }
        }
    }

    private var onboardingControl: some View {
        HStack(spacing: 14) {
            Button(action: toggleRecording) {
                Text(isRecording ? "\(recordingPrompt)  ·  Esc to cancel" : "Use a different shortcut")
            }
            .font(.system(size: 13, design: .rounded))
            .foregroundStyle(isRecording ? OnboardingPalette.foreground : OnboardingPalette.secondary)
            .buttonStyle(.plain)
            .underline(!isRecording)
            .accessibilityHint("Press a key combination, or Escape to cancel")

            if state.recordingShortcut != .default && !isRecording {
                Button("Reset to \(RecordingShortcut.default.displayString)") {
                    message = HotkeyManager.shared.setShortcut(.default)
                }
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(OnboardingPalette.secondary)
                .buttonStyle(.plain)
                .underline()
            }
        }
    }

    private var recordingPrompt: String {
        let symbols = RecordingShortcut(keyCode: 0, flags: heldModifiers).modifierSymbols
        return symbols.isEmpty ? "Press shortcut…" : "\(symbols) …"
    }

    private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        message = nil
        heldModifiers = []
        HotkeyManager.shared.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            handle(event)
            return nil
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        heldModifiers = []
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        HotkeyManager.shared.resume()
    }

    private func handle(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])
        if event.type == .flagsChanged {
            heldModifiers = flags
            return
        }
        guard !event.isARepeat else { return }
        if event.keyCode == UInt16(kVK_Escape) && flags.isEmpty {
            message = nil
            stopRecording()
            return
        }
        let shortcut = RecordingShortcut(keyCode: event.keyCode, flags: flags)
        if let error = HotkeyManager.shared.setShortcut(shortcut) {
            message = error // Keep listening so another combination can be tried.
        } else {
            message = nil
            stopRecording()
        }
    }
}
