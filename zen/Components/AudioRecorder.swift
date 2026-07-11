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

    private let tempDir = FileManager.default.temporaryDirectory

    func startRecording() {
        let audioEngine = AVAudioEngine()
        self.audioEngine = audioEngine
        self.inputNode = audioEngine.inputNode

        let nativeFormat = inputNode!.outputFormat(forBus: 0)
        print("[AudioRecorder] Native format: \(nativeFormat)")

        let fileURL = tempDir.appendingPathComponent("recording_raw_\(Int(Date().timeIntervalSince1970)).wav")
        self.recordedFileURL = fileURL

        guard let audioFile = try? AVAudioFile(forWriting: fileURL, settings: nativeFormat.settings) else {
            print("[AudioRecorder] Failed to create audio file")
            return
        }
        self.audioFile = audioFile

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

        let micPermission = AVCaptureDevice.authorizationStatus(for: .audio)
        if micPermission == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                if granted {
                    DispatchQueue.main.async { self.startEngine(audioEngine) }
                } else {
                    print("[AudioRecorder] Mic permission denied")
                }
            }
        } else if micPermission == .authorized {
            startEngine(audioEngine)
        } else {
            print("[AudioRecorder] Mic permission denied")
        }
    }

    private func startEngine(_ engine: AVAudioEngine) {
        engine.prepare()
        do {
            try engine.start()
            isRecording = true
            print("[AudioRecorder] Engine started successfully")
        } catch {
            print("[AudioRecorder] Failed to start engine: \(error.localizedDescription)")
        }
    }

    func stopRecording() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        inputNode = nil
        audioFile = nil
        isRecording = false
        print("[AudioRecorder] Recording stopped")
    }

    func convertTo16kHzInt16(sourceURL: URL) -> URL? {
        guard let sourceFile = try? AVAudioFile(forReading: sourceURL) else {
            print("[AudioRecorder] Failed to read source")
            return nil
        }

        let srcFormat = sourceFile.processingFormat
        guard srcFormat.commonFormat == .pcmFormatFloat32, srcFormat.channelCount == 1 else {
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

        try? sourceFile.read(into: buffer)
        buffer.frameLength = AVAudioFrameCount(totalFrames)

        let srcRate = srcFormat.sampleRate
        let dstRate: Double = 16000
        let step = Float(srcRate / dstRate)
        let outputCount = Int(Float(totalFrames) / step) + 1

        var int16Samples = [Int16](repeating: 0, count: outputCount)

        for i in 0..<outputCount {
            let srcIndex = Int(Float(i) * step)
            if srcIndex < Int(totalFrames) {
                let sample = floatData.pointee[srcIndex]
                let clamped = max(-1.0, min(1.0, sample))
                int16Samples[i] = Int16(clamped * 32767.0)
            }
        }

        print("[AudioRecorder] Converted \(totalFrames) frames → \(outputCount) Int16 samples")

        let outputURL = tempDir.appendingPathComponent("recording_16khz_\(Int(Date().timeIntervalSince1970)).wav")
        writeWAV(samples: int16Samples, sampleRate: 16000, to: outputURL)
        return outputURL
    }

    private func writeWAV(samples: [Int16], sampleRate: Double, to url: URL) {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        guard let writer = try? FileHandle(forWritingTo: url) else {
            print("[AudioRecorder] Failed to open output file")
            return
        }
        defer { try? writer.close() }

        let data = samples.withUnsafeBytes { Data($0) }
        let dataSize = UInt32(data.count)
        let sampleRateInt = UInt32(sampleRate)
        let byteRate = UInt32(sampleRate * 2)
        let blockAlign = UInt16(2)
        let bitsPerSample = UInt16(16)

        var header = Data()
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

        try? writer.write(contentsOf: header)
        try? writer.write(contentsOf: data)
    }
}
