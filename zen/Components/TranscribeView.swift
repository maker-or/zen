import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

struct TranscribeView: View {
    @Environment(\.zenTheme) private var theme
    @StateObject private var viewModel = TranscribeViewModel()

    var body: some View {
        Group {
            switch viewModel.viewState {
            case .idle:
                DropZoneView(viewModel: viewModel)
                    .padding(24)
            case .processing(let stage, let progress, let mediaInfo):
                ProcessingView(viewModel: viewModel, stage: stage, progress: progress, mediaInfo: mediaInfo)
            case .completed(let transcript, let mediaInfo):
                if let player = viewModel.player {
                    TranscriptWorkspace(viewModel: viewModel, player: player, transcript: transcript, mediaInfo: mediaInfo)
                }
            case .error(let message, let mediaInfo):
                ErrorStateView(viewModel: viewModel, message: message, mediaInfo: mediaInfo)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.smooth(duration: 0.3), value: stateKey)
    }

    /// Animates between screens without animating every progress tick.
    private var stateKey: Int {
        switch viewModel.viewState {
        case .idle: return 0
        case .processing: return 1
        case .completed: return 2
        case .error: return 3
        }
    }
}

// MARK: - Drop Zone

private struct DropZoneView: View {
    @Environment(\.zenTheme) private var theme
    @ObservedObject var viewModel: TranscribeViewModel

    var body: some View {
        let isTargeted = viewModel.isDraggingOver

        VStack(spacing: 28) {
            ZStack {
                Circle()
                    .fill(theme.foreground.opacity(isTargeted ? 0.16 : 0.08))
                    .frame(width: 132, height: 132)
                    .scaleEffect(isTargeted ? 1.08 : 1)

                Image(systemName: isTargeted ? "arrow.down" : "waveform")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(theme.foreground)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 96, height: 96)
                    .glassEffect(.regular, in: .circle)
            }

            VStack(spacing: 8) {
                Text(isTargeted ? "Release to transcribe" : "Drop audio or video")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .contentTransition(.opacity)

                Text("MP4, MOV, MP3, WAV, M4A, FLAC and more")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.foreground.opacity(0.8))
            }

            Button {
                viewModel.selectFile()
            } label: {
                Label("Choose File…", systemImage: "folder")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)

            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text("Transcribed on this Mac. Nothing is uploaded.")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(theme.foreground.opacity(0.7))
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(isTargeted ? theme.foreground.opacity(0.06) : theme.foreground.opacity(0.025))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(
                    isTargeted ? theme.foreground.opacity(0.8) : theme.foreground.opacity(0.08),
                    style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: isTargeted ? [] : [6, 6])
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .onTapGesture { viewModel.selectFile() }
        .dropDestination(for: URL.self) { urls, _ in
            viewModel.handleDroppedURLs(urls)
            return true
        } isTargeted: { targeted in
            viewModel.isDraggingOver = targeted
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isTargeted)
    }
}

// MARK: - Processing

private struct ProcessingView: View {
    @Environment(\.zenTheme) private var theme
    @ObservedObject var viewModel: TranscribeViewModel
    let stage: TranscribeViewModel.Stage
    let progress: Double
    let mediaInfo: MediaInfo?

    private var steps: [TranscribeViewModel.Stage] {
        TranscribeViewModel.Stage.allCases.filter { $0 != .loadingModel || viewModel.includesModelStep }
    }

    var body: some View {
        VStack(spacing: 32) {
            if let mediaInfo {
                FileBadge(mediaInfo: mediaInfo)
            }

            ActivityBars(progress: progress)
                .frame(width: 220, height: 56)

            VStack(spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text(stage == .loadingModel && viewModel.isDownloadingModel ? "Downloading the speech model…" : stage.activeDescription)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Spacer()
                    Text(viewModel.isProgressIndeterminate ? "Working…" : "\(Int(progress * 100))%")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(theme.foreground.opacity(0.8))
                        .contentTransition(.numericText())
                }

                ProgressView(value: viewModel.isProgressIndeterminate ? nil : progress)
                    .progressViewStyle(.linear)
                    .tint(theme.foreground)
                    .animation(.easeOut(duration: 0.3), value: progress)

                HStack(spacing: 0) {
                    ForEach(steps, id: \.self) { step in
                        StepLabel(title: step.title, state: stepState(step))
                        if step != steps.last {
                            Spacer(minLength: 8)
                        }
                    }
                }
                .padding(.top, 4)
            }
            .frame(width: 360)

            Button("Cancel") {
                viewModel.cancel()
            }
            .buttonStyle(.glass)
            .controlSize(.regular)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func stepState(_ step: TranscribeViewModel.Stage) -> StepLabel.State {
        if step.rawValue < stage.rawValue { return .done }
        if step == stage { return .active }
        return .pending
    }
}

private struct StepLabel: View {
    @Environment(\.zenTheme) private var theme
    enum State { case done, active, pending }
    let title: String
    let state: State

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                switch state {
                case .done:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(theme.foreground)
                case .active:
                    ProgressView()
                        .controlSize(.mini)
                case .pending:
                    Image(systemName: "circle")
                        .foregroundStyle(.quaternary)
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .frame(width: 14, height: 14)

            Text(title)
                .font(.system(size: 11, weight: state == .active ? .semibold : .medium))
                .foregroundStyle(theme.foreground.opacity(state == .pending ? 0.7 : 0.85))
        }
    }
}

/// A row of bars that breathe while working and fill in as progress advances.
private struct ActivityBars: View {
    @Environment(\.zenTheme) private var theme
    let progress: Double
    private let count = 28

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 4) {
                ForEach(0..<count, id: \.self) { i in
                    let phase = Double(i) / Double(count)
                    let wave = (sin(t * 3.2 + phase * .pi * 4) + 1) / 2
                    let shape = 0.35 + 0.65 * sin(phase * .pi)
                    Capsule()
                        .fill(phase <= progress ? theme.foreground : theme.foreground.opacity(0.12))
                        .frame(width: 4, height: max(6, 56 * shape * (0.35 + 0.65 * wave)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Workspace

private struct TranscriptWorkspace: View {
    @Environment(\.zenTheme) private var theme
    @ObservedObject var viewModel: TranscribeViewModel
    let player: TranscriptPlayer
    let transcript: Transcript
    let mediaInfo: MediaInfo

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceHeader(viewModel: viewModel, transcript: transcript, mediaInfo: mediaInfo)
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 14)

            if mediaInfo.isVideo {
                Divider()
                    .opacity(0.6)
                splitLayout
            } else {
                Divider()
                    .opacity(0.6)

                ZStack(alignment: .bottom) {
                    transcriptContent(bottomInset: 110)

                    PlayerBar(player: player)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 18)
                }
            }
        }
    }

    /// Video on one half, transcript on the other. Stacks vertically when the
    /// window is too narrow for two useful columns.
    private var splitLayout: some View {
        GeometryReader { geometry in
            let stacked = geometry.size.width < 820
            let layout = stacked ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))

            layout {
                VideoPane(player: player)
                    .frame(
                        width: stacked ? geometry.size.width : geometry.size.width / 2,
                        height: stacked ? geometry.size.height * 0.5 : geometry.size.height
                    )

                Divider()
                    .opacity(0.6)

                transcriptContent(bottomInset: 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func transcriptContent(bottomInset: CGFloat) -> some View {
        if transcript.segments.isEmpty {
            ScrollView {
                Text(transcript.text)
                    .font(.system(size: 15, design: .rounded))
                    .lineSpacing(6)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 26)
                    .padding(.top, 16)
                    .padding(.bottom, bottomInset)
            }
        } else {
            SegmentList(player: player, segments: transcript.segments, bottomInset: bottomInset)
        }
    }
}

private struct WorkspaceHeader: View {
    @Environment(\.zenTheme) private var theme
    @ObservedObject var viewModel: TranscribeViewModel
    let transcript: Transcript
    let mediaInfo: MediaInfo

    private var wordCount: Int {
        transcript.text.split { $0.isWhitespace || $0.isNewline }.count
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: mediaInfo.isVideo ? "film" : "waveform")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(theme.foreground)
                .frame(width: 42, height: 42)
                .background(theme.foreground.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text((mediaInfo.fileName as NSString).deletingPathExtension)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(metadata)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.foreground.opacity(0.8))
                    .monospacedDigit()
            }

            Spacer(minLength: 16)

            HStack(spacing: 8) {
                Button {
                    viewModel.copyTranscript(viewModel.timestampedText(for: transcript))
                } label: {
                    Label(viewModel.copiedFeedback ? "Copied" : "Copy",
                          systemImage: viewModel.copiedFeedback ? "checkmark" : "doc.on.doc")
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.glass)
                .help("Copy with timestamps")

                Menu {
                    Button("Plain Text (.txt)") {
                        viewModel.export(transcript, as: .plainText, mediaInfo: mediaInfo)
                    }
                    if !transcript.segments.isEmpty {
                        Button("Text with Timestamps (.txt)") {
                            viewModel.export(transcript, as: .timestampedText, mediaInfo: mediaInfo)
                        }
                        Button("Subtitles (.srt)") {
                            viewModel.export(transcript, as: .subtitles, mediaInfo: mediaInfo)
                        }
                    }
                    Divider()
                    Button(viewModel.savedToMemosFeedback ? "Added to Memos" : "Add to Memos") {
                        viewModel.addToMemos(transcript.text)
                    }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .menuStyle(.button)
                .buttonStyle(.glass)
                .fixedSize()

                Button {
                    viewModel.reset()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.glass)
                .help("Transcribe another file")
            }
            .controlSize(.large)
        }
    }

    private var metadata: String {
        var parts = [mediaInfo.mediaTypeDescription]
        if mediaInfo.duration > 0 { parts.append(mediaInfo.formattedDuration) }
        parts.append("\(wordCount.formatted()) words")
        parts.append(mediaInfo.formattedFileSize)
        return parts.joined(separator: "  ·  ")
    }
}

// MARK: - Transcript Content

private struct SegmentList: View {
    @Environment(\.zenTheme) private var theme
    let player: TranscriptPlayer
    let segments: [TranscriptSegment]
    let bottomInset: CGFloat

    private var useHours: Bool { (segments.last?.end ?? 0) >= 3600 }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                        SegmentRow(
                            segment: segment,
                            timestamp: TranscribeViewModel.clock(segment.start, hours: useHours),
                            isActive: player.activeSegment == index
                        ) {
                            player.seek(to: segment.start)
                        }
                        .id(index)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, bottomInset)
            }
            .onChange(of: player.activeSegment) { _, index in
                guard let index, player.isPlaying else { return }
                withAnimation(.smooth(duration: 0.4)) {
                    proxy.scrollTo(index, anchor: UnitPoint(x: 0.5, y: 0.35))
                }
            }
        }
    }
}

private struct SegmentRow: View {
    @Environment(\.zenTheme) private var theme
    let segment: TranscriptSegment
    let timestamp: String
    let isActive: Bool
    let onSeek: () -> Void

    @State private var isHovering = false
    @State private var copied = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Button(action: onSeek) {
                Text(timestamp)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isActive ? theme.background : theme.foreground)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(isActive ? theme.foreground : theme.foreground.opacity(isHovering ? 0.14 : 0.08))
                    )
            }
            .buttonStyle(.plain)
            .help("Play from \(timestamp)")

            Text(segment.text)
                .font(.system(size: 15, design: .rounded))
                .lineSpacing(4)
                .foregroundStyle(theme.foreground)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(segment.text, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.foreground.opacity(0.8))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 24, height: 20)
            }
            .buttonStyle(.borderless)
            .opacity(isHovering || copied ? 1 : 0)
            .help("Copy line")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isActive ? theme.foreground.opacity(0.10) : (isHovering ? theme.foreground.opacity(0.04) : .clear))
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2, perform: onSeek)
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .animation(.easeOut(duration: 0.25), value: isActive)
    }
}

// MARK: - Player

/// Floating controls over the transcript, for audio files.
private struct PlayerBar: View {
    @Environment(\.zenTheme) private var theme
    let player: TranscriptPlayer

    var body: some View {
        PlayerControls(player: player)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: 760)
            .glassEffect(.regular, in: .rect(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
    }
}

/// The video at its natural aspect ratio with the playback controls beneath it.
private struct VideoPane: View {
    @Environment(\.zenTheme) private var theme
    let player: TranscriptPlayer

    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)

            ZStack {
                Color.black
                PlayerLayerView(player: player.player, videoGravity: .resizeAspect)

                if !player.isPlaying || isHovering {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 68, height: 68)
                        .glassEffect(.regular.tint(.black.opacity(0.2)), in: .circle)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .aspectRatio(player.videoAspect, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
            .contentShape(Rectangle())
            .onTapGesture { player.togglePlayback() }
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.2), value: player.isPlaying)
            .animation(.easeOut(duration: 0.2), value: isHovering)

            PlayerControls(player: player)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(theme.foreground.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Spacer(minLength: 0)
        }
        .padding(24)
    }
}

private struct PlayerControls: View {
    @Environment(\.zenTheme) private var theme
    let player: TranscriptPlayer

    @State private var scrubTime: TimeInterval?

    private var useHours: Bool { player.duration >= 3600 }

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 4) {
                Button { player.skip(by: -5) } label: {
                    Image(systemName: "gobackward.5")
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 30, height: 30)
                }
                .help("Back 5 seconds")

                Button { player.togglePlayback() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 38, height: 38)
                        .background(theme.foreground, in: Circle())
                        .foregroundStyle(theme.background)
                }
                .help(player.isPlaying ? "Pause" : "Play")

                Button { player.skip(by: 5) } label: {
                    Image(systemName: "goforward.5")
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 30, height: 30)
                }
                .help("Forward 5 seconds")
            }
            .buttonStyle(.plain)

            Text(TranscribeViewModel.clock(scrubTime ?? player.currentTime, hours: useHours))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(theme.foreground.opacity(0.8))
                .frame(minWidth: useHours ? 52 : 38, alignment: .trailing)

            Slider(
                value: Binding(
                    get: { scrubTime ?? player.currentTime },
                    set: { scrubTime = $0 }
                ),
                in: 0...max(player.duration, 0.1)
            ) { editing in
                if !editing, let scrubTime {
                    player.seek(to: scrubTime, play: player.isPlaying)
                    self.scrubTime = nil
                }
            }
            .controlSize(.small)
            .tint(theme.foreground)

            Text(TranscribeViewModel.clock(player.duration.rounded(), hours: useHours))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(theme.foreground.opacity(0.8))
                .frame(minWidth: useHours ? 52 : 38, alignment: .leading)

            Menu {
                ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { speed in
                    Button {
                        player.rate = Float(speed)
                    } label: {
                        if Float(speed) == player.rate {
                            Label(speedLabel(speed), systemImage: "checkmark")
                        } else {
                            Text(speedLabel(speed))
                        }
                    }
                }
            } label: {
                Text(speedLabel(Double(player.rate)))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(theme.foreground.opacity(0.06), in: Capsule())
            .help("Playback speed")
        }
    }

    private func speedLabel(_ speed: Double) -> String {
        speed == speed.rounded() ? "\(Int(speed))×" : "\(speed.formatted())×"
    }
}

// MARK: - Error

private struct ErrorStateView: View {
    @Environment(\.zenTheme) private var theme
    @ObservedObject var viewModel: TranscribeViewModel
    let message: String
    let mediaInfo: MediaInfo?

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.orange)
                .frame(width: 84, height: 84)
                .glassEffect(.regular.tint(.orange.opacity(0.15)), in: .circle)

            VStack(spacing: 8) {
                Text("Couldn’t transcribe this file")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.foreground.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }

            if let mediaInfo {
                FileBadge(mediaInfo: mediaInfo)
            }

            HStack(spacing: 10) {
                if let mediaInfo {
                    Button("Try Again") {
                        viewModel.startTranscription(for: mediaInfo.fileURL)
                    }
                    .buttonStyle(.glassProminent)
                }
                Button("Choose Another File…") {
                    viewModel.reset()
                    viewModel.selectFile()
                }
                .buttonStyle(.glass)
            }
            .controlSize(.large)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Shared

private struct FileBadge: View {
    @Environment(\.zenTheme) private var theme
    let mediaInfo: MediaInfo

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: mediaInfo.isVideo ? "film" : "waveform")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.foreground)
            Text(mediaInfo.fileName)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .truncationMode(.middle)
            Text(mediaInfo.duration > 0 ? mediaInfo.formattedDuration : mediaInfo.formattedFileSize)
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(theme.foreground.opacity(0.8))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: 420)
        .glassEffect(.regular, in: .capsule)
    }
}
