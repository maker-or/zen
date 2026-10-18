import Foundation
import SwiftUI
import Combine
import AppKit
import UniformTypeIdentifiers

@MainActor
final class TranscribeViewModel: ObservableObject {
    enum Stage: Int, Equatable, CaseIterable {
        case loadingModel
        case analyzing
        case preparingAudio
        case transcribing

        var title: String {
            switch self {
            case .loadingModel: return "Load model"
            case .analyzing: return "Analyze"
            case .preparingAudio: return "Prepare audio"
            case .transcribing: return "Transcribe"
            }
        }

        var activeDescription: String {
            switch self {
            case .loadingModel: return "Loading the speech model…"
            case .analyzing: return "Reading the file…"
            case .preparingAudio: return "Preparing audio…"
            case .transcribing: return "Transcribing…"
            }
        }
    }

    enum ViewState: Equatable {
        case idle
        case processing(stage: Stage, progress: Double, mediaInfo: MediaInfo?)
        case completed(transcript: Transcript, mediaInfo: MediaInfo)
        case error(message: String, mediaInfo: MediaInfo?)
    }

    enum ExportFormat {
        case plainText, timestampedText, subtitles
    }

    static let supportedTypes: [UTType] = [
        .movie,
        .video,
        .quickTimeMovie,
        .mpeg4Movie,
        .audio,
        .mp3,
        .wav,
        .aiff,
        UTType(filenameExtension: "m4a") ?? .audio,
        UTType(filenameExtension: "mkv") ?? .movie,
        UTType(filenameExtension: "webm") ?? .movie,
        UTType(filenameExtension: "aac") ?? .audio,
        UTType(filenameExtension: "flac") ?? .audio
    ]

    @Published var viewState: ViewState = .idle
    @Published var isDraggingOver = false
    @Published var copiedFeedback = false
    @Published var savedToMemosFeedback = false
    @Published private(set) var player: TranscriptPlayer?
    /// Whether the model still had to be loaded (or downloaded) for the current
    /// run, so the progress steps only show that step when it actually happened.
    @Published private(set) var includesModelStep = false
    @Published private(set) var isDownloadingModel = false

    @Published private(set) var activeModel: TranscriptionModel = .voz
    private var activeRunID = UUID()

    var isProgressIndeterminate: Bool {
        guard case .processing(.transcribing, _, _) = viewState else { return false }
        return activeModel == .phonon2
    }

    private var currentTask: Task<Void, Never>?

    func selectFile() {
        let panel = NSOpenPanel()
        panel.title = "Select Video or Audio File"
        panel.prompt = "Transcribe"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = Self.supportedTypes

        if panel.runModal() == .OK, let url = panel.url {
            startTranscription(for: url)
        }
    }

    func handleDroppedURLs(_ urls: [URL]) {
        guard let firstURL = urls.first else { return }
        startTranscription(for: firstURL)
    }

    func startTranscription(for fileURL: URL) {
        currentTask?.cancel()
        tearDownPlayer()
        let model = ZenState.shared.transcriptionModel
        let runID = UUID()
        activeRunID = runID
        activeModel = model
        includesModelStep = !TranscriptionService.shared.isModelLoaded(model)
        isDownloadingModel = false
        viewState = .processing(stage: .analyzing, progress: 0, mediaInfo: nil)

        currentTask = Task { [weak self] in
            guard let self else { return }
            var currentMediaInfo: MediaInfo? = nil

            do {
                try Task.checkCancellation()
                if self.includesModelStep {
                    self.viewState = .processing(stage: .loadingModel, progress: 0, mediaInfo: nil)
                    try await TranscriptionService.shared.prepareModel(model) { [weak self] fraction in
                        Task { @MainActor [weak self] in
                            guard let self, self.activeRunID == runID, case .processing(.loadingModel, _, _) = self.viewState else { return }
                            self.isDownloadingModel = fraction < 1
                            self.viewState = .processing(stage: .loadingModel, progress: fraction * 0.4, mediaInfo: nil)
                        }
                    }
                }

                try Task.checkCancellation()
                self.isDownloadingModel = false
                let base = self.includesModelStep ? 0.4 : 0.0
                let span = 1.0 - base

                // Step 1: Extract & convert audio to 16kHz mono WAV
                let result = try await AudioExtractionService.shared.processMediaFile(at: fileURL) { [weak self] stage in
                    guard let self, self.activeRunID == runID else { return }
                    switch stage {
                    case .idle:
                        break
                    case .analyzing:
                        self.viewState = .processing(stage: .analyzing, progress: base + span * 0.05, mediaInfo: currentMediaInfo)
                    case .extractingAudio(let p):
                        self.viewState = .processing(stage: .preparingAudio, progress: base + span * (0.05 + p * 0.15), mediaInfo: currentMediaInfo)
                    case .convertingAudio(let p):
                        self.viewState = .processing(stage: .preparingAudio, progress: base + span * (0.15 + p * 0.1), mediaInfo: currentMediaInfo)
                    case .ready:
                        self.viewState = .processing(stage: .transcribing, progress: base + span * 0.25, mediaInfo: currentMediaInfo)
                    }
                }

                defer { try? FileManager.default.removeItem(at: result.wavURL) }
                try Task.checkCancellation()
                currentMediaInfo = result.mediaInfo
                self.viewState = .processing(stage: .transcribing, progress: base + span * 0.25, mediaInfo: result.mediaInfo)

                // Step 2: Use the model captured when this request started.
                let transcript = try await TranscriptionService.shared.transcribeAudioFile(at: result.wavURL, model: model) { [weak self] p in
                    Task { @MainActor [weak self] in
                        guard self?.activeRunID == runID, case .processing = self?.viewState else { return }
                        self?.viewState = .processing(
                            stage: .transcribing,
                            progress: base + span * (0.25 + p * 0.75),
                            mediaInfo: result.mediaInfo
                        )
                    }
                }

                if Task.isCancelled || self.activeRunID != runID { return }

                if transcript.text.isEmpty {
                    self.viewState = .error(message: "No speech was detected in this file.", mediaInfo: result.mediaInfo)
                } else {
                    self.player = TranscriptPlayer(
                        url: result.mediaInfo.fileURL,
                        duration: result.mediaInfo.duration,
                        hasVideo: result.mediaInfo.isVideo,
                        segments: transcript.segments
                    )
                    self.viewState = .completed(transcript: transcript, mediaInfo: result.mediaInfo)
                }

            } catch {
                if Task.isCancelled || self.activeRunID != runID { return }
                self.viewState = .error(message: error.localizedDescription, mediaInfo: currentMediaInfo)
            }
        }
    }

    func cancel() {
        activeRunID = UUID()
        currentTask?.cancel()
        currentTask = nil
        viewState = .idle
    }

    func reset() {
        activeRunID = UUID()
        currentTask?.cancel()
        currentTask = nil
        tearDownPlayer()
        viewState = .idle
        copiedFeedback = false
        savedToMemosFeedback = false
    }

    private func tearDownPlayer() {
        player?.stop()
        player = nil
    }

    // MARK: - Actions

    func copyTranscript(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        withAnimation {
            copiedFeedback = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            withAnimation {
                self?.copiedFeedback = false
            }
        }
    }

    func addToMemos(_ text: String) {
        ZenState.shared.appendHistory(text)
        withAnimation {
            savedToMemosFeedback = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            withAnimation {
                self?.savedToMemosFeedback = false
            }
        }
    }

    func export(_ transcript: Transcript, as format: ExportFormat, mediaInfo: MediaInfo) {
        let baseName = (mediaInfo.fileName as NSString).deletingPathExtension
        switch format {
        case .plainText:
            save(transcript.text, defaultFileName: "\(baseName).txt")
        case .timestampedText:
            save(timestampedText(for: transcript), defaultFileName: "\(baseName) (timestamps).txt")
        case .subtitles:
            save(srtText(for: transcript), defaultFileName: "\(baseName).srt")
        }
    }

    private func save(_ text: String, defaultFileName: String) {
        let savePanel = NSSavePanel()
        savePanel.title = "Export Transcript"
        savePanel.nameFieldStringValue = defaultFileName
        savePanel.allowedContentTypes = [UTType(filenameExtension: (defaultFileName as NSString).pathExtension) ?? .plainText]

        if savePanel.runModal() == .OK, let url = savePanel.url {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Formatting

    /// One "[mm:ss] text" line per segment.
    func timestampedText(for transcript: Transcript) -> String {
        guard !transcript.segments.isEmpty else { return transcript.text }
        let useHours = (transcript.segments.last?.end ?? 0) >= 3600
        return transcript.segments
            .map { "[\(Self.clock($0.start, hours: useHours))] \($0.text)" }
            .joined(separator: "\n")
    }

    /// The transcript as SubRip subtitles.
    func srtText(for transcript: Transcript) -> String {
        transcript.segments.enumerated().map { index, segment in
            "\(index + 1)\n\(Self.srtTime(segment.start)) --> \(Self.srtTime(segment.end))\n\(segment.text)\n"
        }.joined(separator: "\n")
    }

    static func clock(_ seconds: TimeInterval, hours: Bool) -> String {
        let total = Int(max(0, seconds.isFinite ? seconds : 0))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return hours ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m + h * 60, s)
    }

    private static func srtTime(_ seconds: TimeInterval) -> String {
        let millis = Int((seconds * 1000).rounded())
        return String(format: "%02d:%02d:%02d,%03d",
                      millis / 3_600_000, (millis / 60_000) % 60, (millis / 1000) % 60, millis % 1000)
    }
}
