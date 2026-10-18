import AppKit
import SwiftUI

struct PillContentView: View {
    @ObservedObject var state: ZenState = .shared
    @ObservedObject var recorder: AudioRecorder = .shared

    var body: some View {
        Group {
            switch state.transcriptionState {
            case .idle:
                idleView
            case .recording:
                recordingView
            case .transcribing:
                transcribingView
            case .done:
                doneView
            case .error(let message):
                errorView(message: message)
            }
        }
        .glassEffect(.regular, in: .capsule)
    }

    private var idleView: some View {
        HStack(spacing: 10) {
            Image(systemName: "mic.fill")
                .font(.system(size: 16, weight: .medium))
            Text("Ready")
                .font(.system(size: 13, weight: .medium))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .frame(height: 52)
    }

    private var recordingView: some View {
        WaveformView(level: recorder.audioLevel)
            .frame(width: 80, height: 30)
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
            .frame(height: 52)
    }

    private var transcribingView: some View {
        ProgressView()
            .scaleEffect(0.7)
            .controlSize(.small)
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
            .frame(height: 52)
    }

    private var doneView: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 16))
            .foregroundStyle(.green)
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
            .frame(height: 52)
    }

    private func errorView(message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.yellow)

            Text(message)
                .font(.system(size: 13, weight: .medium))
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
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.yellow.opacity(0.25), in: .rect(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .frame(height: 52)
    }
}

struct WaveformView: View {
    let level: Float
    private let barCount = 20

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
        PillContentView(state: previewState, recorder: AudioRecorder.shared)
            .frame(width: 480, height: 52)
            .padding()
            .background(Color.black.opacity(0.3))
            .onAppear { configure(previewState) }
    }
}
