import Foundation
import Combine
import AppKit

@MainActor
final class TranscriptionService: ObservableObject {
    static let shared = TranscriptionService()

    @Published var isTranscribing = false
    @Published var transcript = ""
    @Published var error: String?

    private let decoder = JSONDecoder()

    private struct TranscriptionResponse: Decodable {
        let transcription: String?
    }

    func transcribe(fileURL: URL, language: String = "en") async {
        isTranscribing = true
        transcript = ""
        error = nil

        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }

        let apiKey = ProcessInfo.processInfo.environment["SMALLEST_API_KEY"]
            ?? UserDefaults.standard.string(forKey: "SMALLEST_API_KEY")
            ?? ""

        guard !apiKey.isEmpty else {
            let msg = "SMALLEST_API_KEY not set"
            print("[Transcription] \(msg)")
            error = msg
            isTranscribing = false
            return
        }

        do {
            let audioData = try Data(contentsOf: fileURL)
            print("[Transcription] Read \(audioData.count) bytes from \(fileURL.lastPathComponent)")

            var components = URLComponents(string: "https://api.smallest.ai/waves/v1/pulse/get_text")!
            components.queryItems = [
                URLQueryItem(name: "language", value: language),
                URLQueryItem(name: "word_timestamps", value: "true"),
            ]

            var request = URLRequest(url: components.url!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            request.httpBody = audioData
            request.timeoutInterval = 120

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            print("[Transcription] API responded with \(data.count) bytes, status: \(httpResponse.statusCode)")

            guard (200...299).contains(httpResponse.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? "no body"
                print("[Transcription] Error response: \(body)")
                throw TranscriptionError.badResponse(httpResponse.statusCode, body)
            }

            let result = try decoder.decode(TranscriptionResponse.self, from: data)
            let text = result.transcription ?? ""
            print("[Transcription] Got text: \"\(text)\" (\(text.count) chars)")

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
        guard let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let transcriptDir = supportDir.appendingPathComponent("Transcripts", isDirectory: true)
        try? FileManager.default.createDirectory(at: transcriptDir, withIntermediateDirectories: true)

        let date = ISO8601DateFormatter().string(from: Date())
        let fileURL = transcriptDir.appendingPathComponent("transcript_\(date).txt")
        try? text.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}

enum TranscriptionError: LocalizedError {
    case badResponse(Int, String)

    var errorDescription: String? {
        switch self {
        case .badResponse(let status, let body):
            return "API error \(status): \(body)"
        }
    }
}
