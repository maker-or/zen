import Foundation
import Combine
import AppKit
import Voz
import DesertAnt

@MainActor
final class TranscriptionService: ObservableObject {
    static let shared = TranscriptionService()

    @Published var isTranscribing = false
    @Published var transcript = ""
    @Published var error: String?
    @Published private(set) var modelStates: [TranscriptionModel: ModelState] = [:]

    enum ModelState: Equatable {
        case loading
        case downloading(Double)
        case ready
        case failed(String)
    }

    private var vozInstance: Voz?
    private var loadTask: Task<Voz, Error>?
    private var downloadProgressHandlers: [@Sendable (Double) -> Void] = []
    private var phononEngine: PhononEngine?
    private var phononLoadTask: Task<PhononEngine, Error>?
    private var phononProgressHandlers: [@Sendable (Double) -> Void] = []

    private init() {}

    /// Whether the model is loaded and ready, so no download or load step is pending.
    func isModelLoaded(_ model: TranscriptionModel) -> Bool {
        switch model {
        case .voz: return vozInstance != nil
        case .phonon2: return phononEngine != nil
        }
    }

    func prepareModel(
        _ model: TranscriptionModel,
        onDownloadProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        guard model.isSupported else {
            throw TranscriptionError.transcriptionFailed("Phonon-2 requires a Mac with Apple silicon.")
        }
        switch model {
        case .voz: _ = try await getVoz(onDownloadProgress: onDownloadProgress)
        case .phonon2: _ = try await getPhonon(onDownloadProgress: onDownloadProgress)
        }
    }

    /// Where a previously verified model lives, so later launches can load it
    /// directly. Voz's own `isDownloaded()`/`Voz()` SHA256 the whole ~460 MB model
    /// on every call, which takes minutes in an unoptimized Debug build.
    private static let modelPathKey = "vozVerifiedModelPath"

    private var verifiedModelPath: String? {
        if let path = UserDefaults.standard.string(forKey: Self.modelPathKey),
           FileManager.default.fileExists(atPath: path) {
            return path
        }
        return Self.completedDownloadPath()
    }

    /// Voz writes `.dal-meta/manifest` only once a download has finished and
    /// passed verification, so a revision folder holding one can be loaded
    /// without re-hashing. If the layout ever changes this finds nothing and the
    /// full `Voz.download` check runs instead.
    private static func completedDownloadPath() -> String? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let root = caches.appendingPathComponent("desert-ant-models/desert-ant-labs/voz", isDirectory: true)
        let revisions = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return revisions
            .sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            .map { root.appendingPathComponent($0).path }
            .first { FileManager.default.fileExists(atPath: "\($0)/.dal-meta/manifest") }
    }

    /// Warm a cached model. The welcome flow or the first transcription owns
    /// the initial download, so choosing "Download later" is respected.
    func warmup() async {
        let model = ZenState.shared.transcriptionModel
        switch model {
        case .voz:
            guard verifiedModelPath != nil else { return }
        case .phonon2:
            guard PhononEngine.distribution.installedModels().contains(where: {
                URL(fileURLWithPath: $0).lastPathComponent == PhononEngine.distribution.revision
            }) else { return }
        }
        try? await prepareModel(model)
    }

    /// Returns the cached Voz instance, downloading and compiling the on-device model if needed.
    /// Concurrent callers (e.g. launch warmup and a transcription) share one load.
    func getVoz(
        onDownloadProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> Voz {
        if let vozInstance {
            return vozInstance
        }
        if let onDownloadProgress {
            downloadProgressHandlers.append(onDownloadProgress)
        }

        let task = loadTask ?? Task { try await loadVoz() }
        loadTask = task
        do {
            return try await task.value
        } catch {
            loadTask = nil
            modelStates[.voz] = .failed(error.localizedDescription)
            throw error
        }
    }

    private func loadVoz() async throws -> Voz {
        modelStates[.voz] = .loading
        defer { downloadProgressHandlers = [] }

        if let path = verifiedModelPath {
            do {
                let instance = try await Self.load(from: path)
                UserDefaults.standard.set(path, forKey: Self.modelPathKey)
                vozInstance = instance
                modelStates[.voz] = .ready
                return instance
            } catch {
                // Files went missing or bad: forget them and verify from scratch.
                print("[Transcription] Cached model failed to load (\(error.localizedDescription)), re-verifying")
                UserDefaults.standard.removeObject(forKey: Self.modelPathKey)
            }
        }

        // Verifies the cached model, downloading it if missing or damaged.
        let path = try await Voz.download { [weak self] progress in
            let fraction = progress.fraction
            Task { @MainActor [weak self] in
                guard let self, self.vozInstance == nil else { return }
                self.modelStates[.voz] = fraction < 1 ? .downloading(fraction) : .loading
                self.downloadProgressHandlers.forEach { $0(fraction) }
            }
        }

        let instance = try await Self.load(from: path)
        UserDefaults.standard.set(path, forKey: Self.modelPathKey)
        vozInstance = instance
        modelStates[.voz] = .ready
        return instance
    }

    private func getPhonon(
        onDownloadProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> PhononEngine {
        if let phononEngine { return phononEngine }
        if let onDownloadProgress { phononProgressHandlers.append(onDownloadProgress) }
        let task = phononLoadTask ?? Task { try await loadPhonon() }
        phononLoadTask = task
        do {
            return try await task.value
        } catch {
            phononLoadTask = nil
            modelStates[.phonon2] = .failed(error.localizedDescription)
            throw error
        }
    }

    private func loadPhonon() async throws -> PhononEngine {
        modelStates[.phonon2] = .loading
        defer { phononProgressHandlers = [] }
        let engine = try await PhononEngine.load { [weak self] fraction in
            Task { @MainActor [weak self] in
                guard let self, self.phononEngine == nil else { return }
                self.modelStates[.phonon2] = fraction < 1 ? .downloading(fraction) : .loading
                self.phononProgressHandlers.forEach { $0(fraction) }
            }
        }
        phononEngine = engine
        modelStates[.phonon2] = .ready
        return engine
    }

    /// Loading compiles the Core ML models, so keep it off the main thread.
    private nonisolated static func load(from path: String) async throws -> Voz {
        try await Task.detached(priority: .userInitiated) {
            try Voz(modelDirectory: URL(fileURLWithPath: path))
        }.value
    }

    /// Transcribes an audio file (e.g. from AudioRecorder or extracted from video)
    /// using the selected model without deleting the source file. Capture the
    /// model once so changing settings cannot switch an in-flight request.
    func transcribeAudioFile(
        at fileURL: URL,
        model: TranscriptionModel? = nil,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> Transcript {
        let model = model ?? ZenState.shared.transcriptionModel
        try Task.checkCancellation()
        try await prepareModel(model)
        try Task.checkCancellation()
        switch model {
        case .voz:
            let voz = try await getVoz()
            let result = try await voz.transcribe(fileURL) { progress in
                onProgress?(progress.fractionCompleted)
            }
            try Task.checkCancellation()
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return Transcript(text: text, segments: TranscriptSegment.group(result.words.map {
                TranscriptWord(text: $0.text, start: $0.start, end: $0.end)
            }))
        case .phonon2:
            let engine = try await getPhonon()
            let result = try await engine.transcribe(fileURL: fileURL)
            onProgress?(1)
            return result
        }
    }

    /// Transcribes a recorded memo file, copies the result to clipboard,
    /// saves it locally, and removes the temporary recording file.
    func transcribe(fileURL: URL) async {
        isTranscribing = true
        transcript = ""
        error = nil

        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }

        do {
            let text = try await transcribeAudioFile(at: fileURL).text
            transcript = text

            if !text.isEmpty {
                copyToClipboard(text)
                saveLocally(text)
                print("[Transcription] Copied to clipboard")
            }

            isTranscribing = false
        } catch {
            let msg = error.localizedDescription
            print("[Transcription] Error: \(msg)")
            self.error = msg
            isTranscribing = false
        }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func saveLocally(_ text: String) {
        let storage = ZenState.shared.storage
        storage.createDirectories()
        let transcriptDir = storage.transcriptsDirectory

        let date = ISO8601DateFormatter().string(from: Date())
        let fileURL = transcriptDir.appendingPathComponent("transcript_\(date).txt")
        try? text.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}

enum TranscriptionError: LocalizedError {
    case noAudioTrackFound
    case conversionFailed(String)
    case transcriptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .noAudioTrackFound:
            return "The selected media does not contain an audio track."
        case .conversionFailed(let msg):
            return "Audio conversion failed: \(msg)"
        case .transcriptionFailed(let msg):
            return "Transcription failed: \(msg)"
        }
    }
}
