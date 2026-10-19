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
    @Published var hasCompletedOnboarding = false {
        didSet { defaults.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }
    @Published var autoPasteEnabled = true {
        didSet { defaults.set(autoPasteEnabled, forKey: "autoPasteEnabled") }
    }
    @Published var transcriptionModel: TranscriptionModel = .voz {
        didSet { defaults.set(transcriptionModel.rawValue, forKey: "transcriptionModel") }
    }
    @Published var isDarkMode: Bool = false {
        didSet { defaults.set(isDarkMode, forKey: "isDarkMode") }
    }

    @Published var themeHex: String = "F5F3EF" {
        didSet { defaults.set(themeHex, forKey: "themeHex") }
    }

    private let historyURL: URL
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        historyURL = supportDir.appendingPathComponent("transcript_history.json")
        hasCompletedOnboarding = defaults.bool(forKey: "hasCompletedOnboarding")
        autoPasteEnabled = defaults.object(forKey: "autoPasteEnabled") as? Bool ?? true
        isDarkMode = defaults.bool(forKey: "isDarkMode")
        themeHex = defaults.string(forKey: "themeHex") ?? (isDarkMode ? "191919" : "F5F3EF")
        transcriptionModel = defaults.string(forKey: "transcriptionModel")
            .flatMap(TranscriptionModel.init(rawValue:)) ?? .voz
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
