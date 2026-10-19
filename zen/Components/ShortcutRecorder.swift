import SwiftUI
import AppKit

/// Click, then press a key combination to change the recording shortcut.
/// Escape cancels. While listening, the global hotkey is paused so pressing
/// the current shortcut doesn't start a recording.
struct ShortcutRecorder: View {
    enum Style { case settings, onboarding }

    var style: Style = .settings
    @Environment(\.zenTheme) private var theme
    @ObservedObject private var state = ZenState.shared
    @ObservedObject private var capture = ShortcutCapture.shared
    private var isRecording: Bool { capture.isCapturing }

    var body: some View {
        VStack(alignment: style == .settings ? .trailing : .leading, spacing: 6) {
            switch style {
            case .settings: settingsControl
            case .onboarding: onboardingControl
            }
            if let message = capture.message {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(style == .settings ? theme.foreground : OnboardingPalette.accent)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(style == .settings ? .trailing : .leading)
            }
        }
        .onDisappear { capture.stop() }
    }

    private var settingsControl: some View {
        HStack(spacing: 8) {
            Button(action: capture.toggle) {
                Text(isRecording ? recordingPrompt : state.recordingShortcut.displayString)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .frame(minWidth: 96)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background {
                        Capsule().fill(theme.foreground.opacity(isRecording ? 0.2 : 0.1))
                            .overlay(Capsule().strokeBorder(theme.foreground.opacity(isRecording ? 0.7 : 0.18), lineWidth: 1))
                    }
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .animation(.easeOut(duration: 0.15), value: isRecording)
            .help(isRecording ? "Press a new shortcut, or Esc to cancel" : "Click to change the shortcut")
            .accessibilityLabel(isRecording ? "Listening for a new shortcut"
                                : "Recording shortcut, \(state.recordingShortcut.spokenDescription)")
            .accessibilityHint("Press a key combination, or Escape to cancel")

            if state.recordingShortcut != .default && !isRecording {
                Button {
                    capture.message = HotkeyManager.shared.setShortcut(.default)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.foreground.opacity(0.75))
                        .frame(width: 26, height: 26)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .help("Reset to \(RecordingShortcut.default.displayString)")
                .accessibilityLabel("Reset to \(RecordingShortcut.default.spokenDescription)")
            }
        }
    }

    private var onboardingControl: some View {
        HStack(spacing: 14) {
            Button(action: capture.toggle) {
                Text(isRecording ? "\(recordingPrompt)  ·  Esc to cancel" : "Use a different shortcut")
            }
            .font(.system(size: 13, design: .rounded))
            .foregroundStyle(isRecording ? OnboardingPalette.foreground : OnboardingPalette.secondary)
            .buttonStyle(.plain)
            .underline(!isRecording)
            .accessibilityHint("Press a key combination, or Escape to cancel")

            if state.recordingShortcut != .default && !isRecording {
                Button("Reset to \(RecordingShortcut.default.displayString)") {
                    capture.message = HotkeyManager.shared.setShortcut(.default)
                }
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(OnboardingPalette.secondary)
                .buttonStyle(.plain)
                .underline()
            }
        }
    }

    private var recordingPrompt: String {
        capture.heldSymbols.isEmpty ? "Press shortcut…" : "\(capture.heldSymbols) …"
    }
}
