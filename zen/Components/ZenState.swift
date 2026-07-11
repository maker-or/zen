import Foundation
import SwiftUI
import Combine

enum TranscriptionState: Equatable {
    case idle
    case recording
    case transcribing
    case done(String)
    case error(String)
}

@MainActor
final class ZenState: ObservableObject {
    static let shared = ZenState()

    @Published var transcriptionState: TranscriptionState = .idle
    @Published var transcriptHistory: [String] = []

    private let historyURL: URL

    init() {
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        historyURL = supportDir.appendingPathComponent("transcript_history.json")
        loadHistory()
    }

    private func loadHistory() {
        guard let data = try? Data(contentsOf: historyURL),
              let history = try? JSONDecoder().decode([String].self, from: data)
        else { return }
        transcriptHistory = history
    }

    func removeFromHistory(_ text: String) {
        guard let index = transcriptHistory.firstIndex(of: text) else { return }
        transcriptHistory.remove(at: index)
        if let data = try? JSONEncoder().encode(transcriptHistory) {
            try? data.write(to: historyURL)
        }
    }

    func appendHistory(_ text: String) {
        transcriptHistory.insert(text, at: 0)
        if transcriptHistory.count > 100 {
            transcriptHistory = Array(transcriptHistory.prefix(100))
        }
        if let data = try? JSONEncoder().encode(transcriptHistory) {
            try? data.write(to: historyURL)
        }
    }
}
