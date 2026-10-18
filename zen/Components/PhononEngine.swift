import Foundation
import PhononCoreML
import DesertAnt

/// The synchronous Core ML API stays on this actor, off the UI thread. An
/// engine is reused, and simultaneous memo/file requests are serialized.
actor PhononEngine {
    nonisolated static let distribution = ModelDistribution(
        repo: "FermionResearch/Phonon-2-CoreML",
        revision: "1143812fd4236522232a8c33e3115f0577e3cd7d",
        files: [.apple: [
            "Phonon-2.mlpackage/", "decoder.bin", "manifest.json", "NOTICE",
            "LICENSE-CODE-Apache-2.0.txt", "LICENSE-WEIGHTS-CC-BY-4.0.txt"
        ]]
    )

    private let transcriber: PhononCoreML.Transcriber

    private init(directory: URL) throws {
        var options = PhononCoreML.Transcriber.Options()
        options.backgroundLoad = true
        transcriber = try PhononCoreML.Transcriber(bundle: directory, options: options)
    }

    nonisolated static func load(progress: @Sendable @escaping (Double) -> Void) async throws -> PhononEngine {
        try await Task.detached(priority: .userInitiated) {
            // The store writes its completion marker only after verification.
            // Match the pinned revision and let Core ML validate loading; avoid
            // hashing hundreds of MB again on every Debug launch.
            if let path = distribution.installedModels().first(where: {
                URL(fileURLWithPath: $0).lastPathComponent == distribution.revision
            }), let cached = try? PhononEngine(directory: URL(fileURLWithPath: path)) {
                return cached
            }
            // Reuse the app's verified, resumable model store. It checks the
            // pinned revision and file hashes, and works offline once cached.
            let stored = try await distribution.resolve { progress($0.fraction) }
            return try PhononEngine(directory: URL(fileURLWithPath: stored.rootPath))
        }.value
    }

    func transcribe(fileURL: URL) throws -> Transcript {
        try Task.checkCancellation()
        let result = try transcriber.transcribe(url: fileURL)
        try Task.checkCancellation()
        return Transcript(
            text: result.text.trimmingCharacters(in: .whitespacesAndNewlines),
            segments: TranscriptSegment.group(result.words.map {
                TranscriptWord(text: $0.text, start: $0.start, end: $0.end)
            })
        )
    }
}
