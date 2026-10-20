import AppKit
import SwiftUI

/// The recording widget: a small pill that stays out of the way while idle
/// and grows only as much as each state needs. Click it to start or finish a
/// recording; right-click it to move or hide it.
struct PillContentView: View {
    @ObservedObject var state: ZenState = .shared
    @ObservedObject var recorder: AudioRecorder = .shared
    @ObservedObject var hover: PillHover

    private var isHovering: Bool { hover.isHovering }

    var body: some View {
        pill
            // Where the pill is, so only it takes clicks; see `PillPanelManager.updateHover`.
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                PillPanelManager.shared.pillFrameChanged($0)
            }
            .padding(.vertical, 6) // Room for the glass edge.
            // Against the screen edge it's placed at, growing away from it.
            .frame(maxWidth: .infinity, maxHeight: .infinity,
                   alignment: state.widgetPosition == .top ? .top : .bottom)
    }

    /// One glass capsule whose size animates between states while its
    /// contents cross-fade.
    private var pill: some View {
        ZStack {
            switch state.transcriptionState {
            case .idle:
                idleView.transition(Self.swap)
            case .recording:
                recordingView.transition(Self.swap)
            case .transcribing:
                transcribingView.transition(Self.swap)
            case .done:
                doneView.transition(Self.swap)
            case .error(let message):
                errorView(message: message).transition(Self.swap)
            }
        }
        .clipShape(.capsule) // Nothing shows outside the pill while it resizes.
        .glassEffect(.regular, in: .capsule)
        .contentShape(.capsule)
        .onTapGesture { PillPanelManager.shared.widgetClicked() }
        .contextMenu { menu }
        .animation(.smooth(duration: 0.32), value: state.transcriptionState)
        .animation(.smooth(duration: 0.24), value: isHovering)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(state.transcriptionState == .recording ? "Finishes the recording" : "Starts a recording")
    }

    private static let swap = AnyTransition.opacity.combined(with: .scale(scale: 0.85))

    /// A few resting bars; hovering shows how to start.
    private var idleView: some View {
        HStack(spacing: 6) {
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { _ in
                    Capsule().fill(.primary.opacity(0.55)).frame(width: 2, height: 4)
                }
            }
            if isHovering {
                Text("Hold \(state.recordingShortcut.displayString)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.8))
                    .fixedSize()
                    // Gone quickly as the pill starts to shrink; in once it has grown.
                    .transition(.asymmetric(
                        insertion: .opacity.animation(.smooth(duration: 0.18).delay(0.1)),
                        removal: .opacity.animation(.easeOut(duration: 0.08))))
            }
        }
        .padding(.horizontal, isHovering ? 12 : 10)
        .frame(height: isHovering ? 26 : 16)
        .accessibilityLabel("Zen, ready. Hold \(state.recordingShortcut.spokenDescription) to talk")
    }

    private var recordingView: some View {
        WaveformView(level: recorder.audioLevel, barCount: 14)
            .frame(width: 48, height: 16)
            .padding(.horizontal, 14)
            .frame(height: 30)
            .accessibilityLabel("Recording")
    }

    private var transcribingView: some View {
        ProgressView()
            .controlSize(.mini)
            .padding(.horizontal, 22)
            .frame(height: 30)
            .accessibilityLabel("Transcribing")
    }

    private var doneView: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.green)
            .padding(.horizontal, 22)
            .frame(height: 30)
            .accessibilityLabel("Done")
    }

    private func errorView(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.yellow)

            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: true, vertical: false)

            if message.localizedCaseInsensitiveContains("mic") {
                Button {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Text("Open Settings")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.yellow.opacity(0.25), in: .rect(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 30)
    }

    @ViewBuilder private var menu: some View {
        Picker("Position", selection: $state.widgetPosition) {
            ForEach(WidgetPosition.allCases) { Text($0.title).tag($0) }
        }
        Toggle("Show When Idle", isOn: $state.showsIdleWidget)
    }
}

struct WaveformView: View {
    let level: Float
    var barCount = 20

    var body: some View {
        GeometryReader { geometry in
            let spacing: CGFloat = 2
            let barWidth = (geometry.size.width - spacing * CGFloat(barCount - 1)) / CGFloat(barCount)
            let maxHeight = geometry.size.height

            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    let phase = Float(index) / Float(barCount) * .pi * 2
                    let variation = 0.3 + 0.7 * (0.5 + 0.5 * sin(phase))
                    let heightPercent = min(CGFloat(level) * CGFloat(variation) * 0.9 + 0.05, 1.0)
                    let barHeight = maxHeight * heightPercent

                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(.primary)
                        .frame(width: barWidth, height: max(2, barHeight))
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .animation(.easeOut(duration: 0.08), value: level)
        }
    }
}

#Preview("Idle") {
    PillPreview { $0.transcriptionState = .idle }
}

#Preview("Recording") {
    PillPreview { $0.transcriptionState = .recording }
}

#Preview("Transcribing") {
    PillPreview { $0.transcriptionState = .transcribing }
}

#Preview("Done") {
    PillPreview { $0.transcriptionState = .done("Hello world") }
}

#Preview("Error") {
    PillPreview { $0.transcriptionState = .error("Mic access denied in System Settings") }
}

struct PillPreview: View {
    let configure: (ZenState) -> Void
    @StateObject private var previewState = ZenState()

    var body: some View {
        PillContentView(state: previewState, recorder: AudioRecorder.shared, hover: PillHover())
            .frame(width: 420, height: 56)
            .padding()
            .background(Color.black.opacity(0.3))
            .onAppear { configure(previewState) }
    }
}
