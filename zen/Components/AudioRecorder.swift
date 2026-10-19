import os
import AVFoundation
import Combine

@MainActor
final class AudioRecorder: NSObject, ObservableObject {
    static let shared = AudioRecorder()

    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var audioFile: AVAudioFile?

    @Published var isRecording = false
    @Published var recordedFileURL: URL?
    @Published var audioLevel: Float = 0

    private let tempDir: URL

    init(tempDirectory: URL = FileManager.default.temporaryDirectory) {
        tempDir = tempDirectory
        super.init()
    }

    /// Starts capturing from the default input. Returns false when the
    /// microphone couldn't be opened, so callers never show a recording that
    /// isn't happening. Microphone permission must already be granted.
    @discardableResult
    func startRecording() -> Bool {
        recordedFileURL = nil
        let audioEngine = AVAudioEngine()
        self.audioEngine = audioEngine
        self.inputNode = audioEngine.inputNode

        let nativeFormat = inputNode!.outputFormat(forBus: 0)
        print("[AudioRecorder] Native format: \(nativeFormat)")

        let fileURL = tempDir.appendingPathComponent("recording_raw_\(UUID().uuidString).wav")

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            Log.recording.error("Failed to create recording directory: \(error.localizedDescription, privacy: .public)")
            return false
        }

        guard nativeFormat.sampleRate > 0, nativeFormat.channelCount > 0 else {
            Log.recording.error("No usable input device (format \(nativeFormat.description, privacy: .public))")
            return false
        }
        guard let audioFile = try? AVAudioFile(forWriting: fileURL, settings: nativeFormat.settings) else {
            Log.recording.error("Failed to create audio file")
            return false
        }
        self.audioFile = audioFile
        self.recordedFileURL = fileURL

        inputNode!.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, _ in
            guard let self else { return }
            try? self.audioFile?.write(from: buffer)
            if let channelData = buffer.floatChannelData {
                let frames = buffer.frameLength
                var sum: Float = 0
                for i in 0..<Int(frames) {
                    let sample = channelData.pointee[i]
                    sum += sample * sample
                }
                let rms = sqrt(sum / Float(frames))
                let scaled = min(rms * 5, 1.0)
                Task { @MainActor in
                    self.audioLevel = scaled
                }
            }
        }

        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            Log.recording.error("Microphone permission not granted")
            discardFailedStart(fileURL)
            return false
        }
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            Log.recording.error("Failed to start audio engine: \(error.localizedDescription, privacy: .public)")
            discardFailedStart(fileURL)
            return false
        }
        isRecording = true
        Log.recording.notice("Recording started (\(nativeFormat.sampleRate, format: .fixed(precision: 0)) Hz, \(nativeFormat.channelCount) ch)")
        return true
    }

    private func discardFailedStart(_ fileURL: URL) {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        inputNode = nil
        audioFile = nil
        recordedFileURL = nil
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Keeps the mic open for `tail` seconds before stopping, so the last word
    /// isn't clipped when the hotkey is pressed right as speech ends, and the
    /// tap's in-flight buffer gets written instead of dropped.
    func stopRecording(tail: TimeInterval = 0.4) async {
        if tail > 0, audioEngine != nil {
            try? await Task.sleep(for: .seconds(tail))
        }
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        inputNode = nil
        audioFile = nil
        isRecording = false
        Log.recording.notice("Recording stopped")
    }

    func convertTo16kHzInt16(sourceURL: URL) -> URL? {
        guard let sourceFile = try? AVAudioFile(forReading: sourceURL) else {
            print("[AudioRecorder] Failed to read source")
            return nil
        }

        let srcFormat = sourceFile.processingFormat
        let channelCount = Int(srcFormat.channelCount)
        guard srcFormat.commonFormat == .pcmFormatFloat32, channelCount >= 1 else {
            print("[AudioRecorder] Unexpected source format: \(srcFormat)")
            return nil
        }

        let totalFrames = sourceFile.length
        guard let buffer = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: AVAudioFrameCount(totalFrames)),
              let floatData = buffer.floatChannelData
        else {
            print("[AudioRecorder] Failed to allocate buffer")
            return nil
        }

        do {
            try sourceFile.read(into: buffer)
        } catch {
            print("[AudioRecorder] Failed to read recording: \(error.localizedDescription)")
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(totalFrames)

        let srcRate = srcFormat.sampleRate
        let dstRate: Double = 16000
        let step = Float(srcRate / dstRate)
        let outputCount = Int(Float(totalFrames) / step) + 1
        // Trailing silence gives the model right context for the final word;
        // without it the last word is often dropped.
        let paddingCount = Int(dstRate * 0.6)

        var int16Samples = [Int16](repeating: 0, count: outputCount + paddingCount)

        for i in 0..<outputCount {
            let srcIndex = Int(Float(i) * step)
            if srcIndex < Int(totalFrames) {
                var sample: Float = 0
                for ch in 0..<channelCount {
                    sample += floatData[ch][srcIndex]
                }
                sample /= Float(channelCount)
                let clamped = max(-1.0, min(1.0, sample))
                int16Samples[i] = Int16(clamped * 32767.0)
            }
        }

        print("[AudioRecorder] Converted \(totalFrames) frames → \(outputCount) Int16 samples")

        let outputURL = tempDir.appendingPathComponent("recording_16khz_\(UUID().uuidString).wav")
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            try writeWAV(samples: int16Samples, sampleRate: 16000, to: outputURL)
            return outputURL
        } catch {
            print("[AudioRecorder] Failed to write converted recording: \(error.localizedDescription)")
            return nil
        }
    }

    private func writeWAV(samples: [Int16], sampleRate: Double, to url: URL) throws {
        let dataSize = UInt32(samples.count * MemoryLayout<Int16>.size)
        let sampleRateInt = UInt32(sampleRate)
        let byteRate = UInt32(sampleRate * 2)
        let blockAlign = UInt16(2)
        let bitsPerSample = UInt16(16)

        var header = Data()
        header.reserveCapacity(44 + Int(dataSize))
        header.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        withUnsafeBytes(of: 36 + dataSize) { header.append(contentsOf: $0) }
        header.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"
        header.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        withUnsafeBytes(of: UInt32(16)) { header.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt16(1)) { header.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt16(1)) { header.append(contentsOf: $0) }
        withUnsafeBytes(of: sampleRateInt) { header.append(contentsOf: $0) }
        withUnsafeBytes(of: byteRate) { header.append(contentsOf: $0) }
        withUnsafeBytes(of: blockAlign) { header.append(contentsOf: $0) }
        withUnsafeBytes(of: bitsPerSample) { header.append(contentsOf: $0) }
        header.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        withUnsafeBytes(of: dataSize) { header.append(contentsOf: $0) }

        samples.withUnsafeBytes { header.append(contentsOf: $0) }
        // Publish the complete WAV in one atomic write. A failed write throws;
        // conversion must never return a path that the transcriber cannot open.
        try header.write(to: url, options: .atomic)
    }
}
