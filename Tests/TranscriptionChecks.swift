import Foundation
import Darwin
import AVFoundation

/// Standalone checks linked against the app's built model dependencies.
@main
@MainActor
struct TranscriptionChecks {
    static func main() async throws {
        setbuf(stdout, nil)
        let suiteName = "ZenTranscriptionChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(suiteName)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let storage = ZenStorage(applicationSupport: scratch)
        let state = ZenState(defaults: defaults, storage: storage)
        precondition(state.autoPasteEnabled, "Automatic paste defaults to enabled, subject to Accessibility permission")
        state.autoPasteEnabled = false
        precondition(!ZenState(defaults: defaults, storage: storage).autoPasteEnabled, "Disabling automatic paste must persist")
        state.autoPasteEnabled = true
        precondition(!state.hasCompletedOnboarding, "First launch must show onboarding")
        state.hasCompletedOnboarding = true
        precondition(ZenState(defaults: defaults, storage: storage).hasCompletedOnboarding, "Completed onboarding must stay dismissed after relaunch")
        precondition(state.transcriptionModel == .voz, "Existing installations must default to Voz")
        state.transcriptionModel = .phonon2
        precondition(ZenState(defaults: defaults, storage: storage).transcriptionModel == .phonon2, "Selection must survive relaunch")
        state.transcriptionModel = .voz
        precondition(ZenState(defaults: defaults, storage: storage).transcriptionModel == .voz, "Switching back must persist")
        defaults.set("unknown-future-model", forKey: "transcriptionModel")
        precondition(ZenState(defaults: defaults, storage: storage).transcriptionModel == .voz, "Unknown settings must fall back to Voz")
        precondition(TranscriptSegment.group([]).isEmpty)
        let words = [
            TranscriptWord(text: "Hello", start: 0, end: 0.5),
            TranscriptWord(text: "world.", start: 0.6, end: 1),
            TranscriptWord(text: "Next", start: 2.5, end: 3)
        ]
        let segments = TranscriptSegment.group(words)
        precondition(segments == [
            TranscriptSegment(start: 0, end: 1, text: "Hello world."),
            TranscriptSegment(start: 2.5, end: 3, text: "Next")
        ], "Grouping must preserve words and timing, splitting at pauses")
        let sentenceWords = [
            TranscriptWord(text: "Long", start: 0, end: 4.5),
            TranscriptWord(text: "sentence.", start: 4.6, end: 5),
            TranscriptWord(text: "Next", start: 5.1, end: 6)
        ]
        precondition(TranscriptSegment.group(sentenceWords).map(\.text) == ["Long sentence.", "Next"], "Long sentences should split at punctuation")

        let service = TranscriptionService.shared
        let cancelled = Task {
            try await service.transcribeAudioFile(at: URL(fileURLWithPath: "/not-a-file.wav"), model: .phonon2)
        }
        cancelled.cancel()
        do {
            _ = try await cancelled.value
            preconditionFailure("A cancelled request must not load a model or transcribe")
        } catch is CancellationError { }
        precondition(service.modelStates[.phonon2] == nil, "Cancellation must not start downloading")
        print("PASS: default model, persisted switching, invalid preference fallback, timestamps, sentence grouping, cancellation")
        guard try verifyRecordingFiles() else { exit(1) }

        if CommandLine.arguments.count > 1 {
            let fileURL = URL(fileURLWithPath: CommandLine.arguments[1])
            async let first: Void = service.prepareModel(.phonon2)
            async let second: Void = service.prepareModel(.phonon2)
            try await first
            try await second
            precondition(service.isModelLoaded(.phonon2))
            precondition(service.modelStates[.phonon2] == .ready)
            print("PASS: concurrent preparation shares a single Phonon-2 load")
            // Exercise the same WAV conversion used by the recording pill,
            // rather than bypassing it with a model's reference FLAC file.
            let recorder = AudioRecorder()
            guard let recordingURL = recorder.convertTo16kHzInt16(sourceURL: fileURL) else {
                fatalError("Reference audio could not be converted to a recorded WAV")
            }
            defer { try? FileManager.default.removeItem(at: recordingURL) }
            for model in TranscriptionModel.allCases {
                let result = try await service.transcribeAudioFile(at: recordingURL, model: model)
                precondition(result.text.lowercased().contains("yellow lamps"), "Expected known speech from the public reference clip")
                precondition(!result.segments.isEmpty, "Word timestamps must reach the transcript workspace")
                precondition(result.segments.allSatisfy { $0.start >= 0 && $0.end >= $0.start && !$0.text.isEmpty })
                precondition(zip(result.segments, result.segments.dropFirst()).allSatisfy { $0.start <= $1.start })
                print("PASS: \(model.name) real audio, \(result.segments.count) timed segment(s): \(result.text)")
            }
        }
    }

    private static func verifyRecordingFiles() throws -> Bool {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("zen-recording-checks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.wav")
        try makeAudioFixture(at: source)
        let recorder = AudioRecorder(tempDirectory: directory)
        let outputs = try (0..<8).map { _ -> URL in
            guard let url = recorder.convertTo16kHzInt16(sourceURL: source) else {
                throw NSError(domain: "RecordingChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: "WAV conversion failed"])
            }
            return url
        }
        let uniquePaths = Set(outputs).count == outputs.count
        if !uniquePaths {
            fputs("FAIL: recordings share a temporary path; cleaning up one can delete another's input.\n", stderr)
        }
        let blockedDirectory = directory.appendingPathComponent("not-a-directory")
        try Data().write(to: blockedDirectory)
        let failedWrite = AudioRecorder(tempDirectory: blockedDirectory).convertTo16kHzInt16(sourceURL: source)
        if failedWrite != nil {
            fputs("FAIL: conversion reports success with a nonexistent file when writing fails.\n", stderr)
        }
        guard uniquePaths, failedWrite == nil else { return false }
        try FileManager.default.removeItem(at: outputs[0])
        for output in outputs.dropFirst() {
            let audio = try AVAudioFile(forReading: output)
            precondition(audio.processingFormat.sampleRate == 16000)
            precondition(audio.processingFormat.channelCount == 1 && audio.length > 0)
        }
        precondition(FileManager.default.fileExists(atPath: source.path), "Conversion must retain the source")
        print("PASS: unique WAV paths, independent cleanup, completed 16 kHz mono files, write failures rejected")
        return true
    }

    private static func makeAudioFixture(at url: URL) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 480)!
        buffer.frameLength = 480
        buffer.floatChannelData![0].update(repeating: 0, count: 480)
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }
}
