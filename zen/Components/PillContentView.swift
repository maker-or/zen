import SwiftUI

struct PillContentView: View {
    @ObservedObject var state: ZenState = .shared
    @ObservedObject var recorder: AudioRecorder = .shared

    var body: some View {
        switch state.transcriptionState {
        case .idle:
            idleView
        case .recording:
            recordingView
        case .transcribing:
            transcribingView
        case .done(let text):
            doneView(text: text)
        case .error(let message):
            errorView(message: message)
        }
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
        .glassEffect(Glass.regular.tint(Color.white.opacity(0.3)).interactive(true), in: .rect(cornerRadius: 26))
    }

    private var recordingView: some View {
        HStack(spacing: 14) {
            WaveformView(level: recorder.audioLevel)
                .frame(width: 80, height: 30)
            
        }
     
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .frame(height: 52)
        .glassEffect(Glass.regular.interactive(true), in: .rect(cornerRadius: 26))
    }

    private var transcribingView: some View {
        HStack(spacing: 10) {
            ProgressView()
                .scaleEffect(0.7)
                .controlSize(.small)
            
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .frame(height: 52)
        .glassEffect(Glass.regular.interactive(true), in: .rect(cornerRadius: 26))
    }

    private func doneView(text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(.green)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .frame(height: 52)
        .glassEffect(Glass.regular.interactive(true), in: .rect(cornerRadius: 26))
    }

    private func errorView(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundColor(.yellow)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .frame(height: 52)
        .glassEffect(Glass.regular.tint(Color.yellow.opacity(0.3)).interactive(true), in: .rect(cornerRadius: 26))
    }
}

struct WaveformView: View {
    let level: Float

    private let barCount = 20

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 2
            let barWidth = (geo.size.width - spacing * CGFloat(barCount - 1)) / CGFloat(barCount)
            let maxHeight = geo.size.height

            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { i in
                    let phase = Float(i) / Float(barCount) * .pi * 2
                    let variation = 0.3 + 0.7 * (0.5 + 0.5 * sin(phase))
                    let heightPercent = min(CGFloat(level) * CGFloat(variation) * 0.9 + 0.05, 1.0)
                    let barHeight = maxHeight * heightPercent

                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(.black)
                        .frame(width: barWidth, height: max(2, barHeight))
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .animation(.easeOut(duration: 0.08), value: level)
        }
    }
}

#Preview("Idle") {
    PillPreview { state in
        state.transcriptionState = .idle
    }
}

#Preview("Recording") {
    PillPreview { state in
        state.transcriptionState = .recording
    }
}

#Preview("Transcribing") {
    PillPreview { state in
        state.transcriptionState = .transcribing
    }
}

#Preview("Done") {
    PillPreview { state in
        state.transcriptionState = .done("Hello world")
    }
}

#Preview("Error") {
    PillPreview { state in
        state.transcriptionState = .error("API error 401: Unauthorized")
    }
}

struct PillPreview: View {
    let configure: (ZenState) -> Void
    @StateObject private var previewState = ZenState()

    var body: some View {
        PillContentView(state: previewState, recorder: AudioRecorder.shared)
            .frame(width: 480, height: 52)
            .padding()
            .background(Color.black.opacity(0.3))
            .onAppear {
                configure(previewState)
            }
    }
}
