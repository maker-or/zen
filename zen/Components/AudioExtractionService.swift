import Foundation
import AVFoundation
import UniformTypeIdentifiers

struct MediaInfo: Equatable {
    let fileURL: URL
    let fileName: String
    let fileSize: Int64
    let duration: TimeInterval
    let isVideo: Bool
    let hasAudio: Bool

    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    var formattedDuration: String {
        guard duration > 0 && !duration.isNaN && !duration.isInfinite else { return "--:--" }
        let totalSeconds = Int(duration.rounded())
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    var mediaTypeDescription: String {
        isVideo ? "Video" : "Audio"
    }

    var systemIcon: String {
        isVideo ? "video.fill" : "waveform"
    }
}

enum MediaProcessingStage: Equatable {
    case idle
    case analyzing
    case extractingAudio(progress: Double)
    case convertingAudio(progress: Double)
    case ready
}

final class AudioExtractionService {
    static let shared = AudioExtractionService()

    private let tempDir = FileManager.default.temporaryDirectory

    private init() {}

    /// Inspects media at a given URL to determine if it has audio, video, and its duration/size.
    func inspectMedia(at url: URL) async throws -> MediaInfo {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isScoped {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let asset = AVURLAsset(url: url)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)

        var duration: TimeInterval = 0
        if let cmDuration = try? await asset.load(.duration) {
            let seconds = CMTimeGetSeconds(cmDuration)
            if !seconds.isNaN && !seconds.isInfinite {
                duration = seconds
            }
        }

        let fileSize: Int64 = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0

        return MediaInfo(
            fileURL: url,
            fileName: url.lastPathComponent,
            fileSize: fileSize,
            duration: duration,
            isVideo: !videoTracks.isEmpty,
            hasAudio: !audioTracks.isEmpty
        )
    }

    /// Extracts and converts media file (video or audio) into a 16kHz mono 16-bit WAV file ready for transcription.
    /// Returns the URL of the temporary WAV file and MediaInfo.
    func processMediaFile(
        at fileURL: URL,
        onStageChanged: ((MediaProcessingStage) -> Void)? = nil
    ) async throws -> (wavURL: URL, mediaInfo: MediaInfo) {
        let isScoped = fileURL.startAccessingSecurityScopedResource()
        defer {
            if isScoped {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        onStageChanged?(.analyzing)
        let mediaInfo = try await inspectMedia(at: fileURL)

        guard mediaInfo.hasAudio else {
            throw TranscriptionError.noAudioTrackFound
        }

        let tempWAVURL = tempDir.appendingPathComponent("zen_audio_\(UUID().uuidString).wav")

        if mediaInfo.isVideo {
            // Step 1: Extract audio track to temporary M4A container
            onStageChanged?(.extractingAudio(progress: 0.25))
            let tempM4AURL = tempDir.appendingPathComponent("zen_extracted_\(UUID().uuidString).m4a")
            defer {
                try? FileManager.default.removeItem(at: tempM4AURL)
            }

            try await extractAudioTrack(from: fileURL, to: tempM4AURL)

            // Step 2: Convert M4A to 16kHz mono Int16 WAV
            onStageChanged?(.convertingAudio(progress: 0.70))
            try convertAudioTo16kHzWAV(inputURL: tempM4AURL, outputURL: tempWAVURL)

        } else {
            // Direct audio file: convert directly to 16kHz mono WAV
            onStageChanged?(.convertingAudio(progress: 0.50))
            do {
                try convertAudioTo16kHzWAV(inputURL: fileURL, outputURL: tempWAVURL)
            } catch {
                // Fallback for uncommon audio containers: extract via AVAssetExportSession first
                let tempM4AURL = tempDir.appendingPathComponent("zen_extracted_\(UUID().uuidString).m4a")
                defer {
                    try? FileManager.default.removeItem(at: tempM4AURL)
                }
                try await extractAudioTrack(from: fileURL, to: tempM4AURL)
                try convertAudioTo16kHzWAV(inputURL: tempM4AURL, outputURL: tempWAVURL)
            }
        }

        onStageChanged?(.ready)
        return (wavURL: tempWAVURL, mediaInfo: mediaInfo)
    }

    /// Uses AVAssetExportSession to export the audio track of any media file into an M4A audio file.
    private func extractAudioTrack(from sourceURL: URL, to destinationURL: URL) async throws {
        try? FileManager.default.removeItem(at: destinationURL)

        let asset = AVURLAsset(url: sourceURL)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw TranscriptionError.conversionFailed("Unable to create audio export session")
        }

        if #available(macOS 15.0, *) {
            try await exportSession.export(to: destinationURL, as: .m4a)
        } else {
            exportSession.outputURL = destinationURL
            exportSession.outputFileType = .m4a
            await exportSession.export()

            if let error = exportSession.error {
                throw TranscriptionError.conversionFailed(error.localizedDescription)
            }
            if exportSession.status != .completed {
                throw TranscriptionError.conversionFailed("Audio export did not complete")
            }
        }
    }

    /// Converts any readable audio file into a 16kHz 16-bit mono PCM WAV file.
    private func convertAudioTo16kHzWAV(inputURL: URL, outputURL: URL) throws {
        try? FileManager.default.removeItem(at: outputURL)

        let inputFile = try AVAudioFile(forReading: inputURL)
        let srcFormat = inputFile.processingFormat

        // Target format: 16kHz, 1 channel (mono), Int16 PCM
        guard let dstFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) else {
            throw TranscriptionError.conversionFailed("Failed to create target audio format (16kHz mono)")
        }

        guard let converter = AVAudioConverter(from: srcFormat, to: dstFormat) else {
            throw TranscriptionError.conversionFailed("Failed to initialize audio converter for \(srcFormat)")
        }

        let outputFile = try AVAudioFile(
            forWriting: outputURL,
            settings: dstFormat.settings,
            commonFormat: .pcmFormatInt16,
            interleaved: false
        )

        let bufferSize: AVAudioFrameCount = 4096
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: bufferSize) else {
            throw TranscriptionError.conversionFailed("Failed to allocate audio input buffer")
        }

        let ratio = 16000.0 / srcFormat.sampleRate
        let outCapacity = AVAudioFrameCount(Double(bufferSize) * ratio) + 1024
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: dstFormat, frameCapacity: outCapacity) else {
            throw TranscriptionError.conversionFailed("Failed to allocate audio output buffer")
        }

        var isDone = false
        while !isDone {
            var convError: NSError?
            let status = converter.convert(to: outputBuffer, error: &convError) { inNumPackets, outStatus in
                if isDone {
                    outStatus.pointee = .endOfStream
                    return nil
                }
                do {
                    try inputFile.read(into: inputBuffer, frameCount: inNumPackets)
                    if inputBuffer.frameLength == 0 {
                        outStatus.pointee = .endOfStream
                        isDone = true
                        return nil
                    }
                    outStatus.pointee = .haveData
                    return inputBuffer
                } catch {
                    outStatus.pointee = .endOfStream
                    isDone = true
                    return nil
                }
            }

            if let error = convError {
                throw TranscriptionError.conversionFailed(error.localizedDescription)
            }

            if outputBuffer.frameLength > 0 {
                try outputFile.write(from: outputBuffer)
            }

            if status == .endOfStream {
                break
            }
        }

        // Trailing silence gives the model right context for the final word;
        // without it speech that runs to the end of the file loses its last word.
        let paddingFrames = AVAudioFrameCount(dstFormat.sampleRate * 0.6)
        if let silence = AVAudioPCMBuffer(pcmFormat: dstFormat, frameCapacity: paddingFrames),
           let channel = silence.int16ChannelData {
            channel[0].update(repeating: 0, count: Int(paddingFrames))
            silence.frameLength = paddingFrames
            try outputFile.write(from: silence)
        }
    }
}
