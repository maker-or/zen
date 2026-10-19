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
    @Published private(set) var transcriptHistory: [Memo] = []
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
    /// Change through `HotkeyManager.setShortcut(_:)` so a shortcut that can't
    /// be registered is never saved.
    @Published var recordingShortcut: RecordingShortcut = .default {
        didSet { defaults.set(try? JSONEncoder().encode(recordingShortcut), forKey: "recordingShortcut") }
    }

    let storage: ZenStorage
    private var historyURL: URL { storage.historyURL }
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, storage: ZenStorage = .standard) {
        self.defaults = defaults
        self.storage = storage
        storage.migrateLegacyData()
        hasCompletedOnboarding = defaults.bool(forKey: "hasCompletedOnboarding")
        autoPasteEnabled = defaults.object(forKey: "autoPasteEnabled") as? Bool ?? true
        isDarkMode = defaults.bool(forKey: "isDarkMode")
        themeHex = defaults.string(forKey: "themeHex") ?? (isDarkMode ? "191919" : "F5F3EF")
        transcriptionModel = defaults.string(forKey: "transcriptionModel")
            .flatMap(TranscriptionModel.init(rawValue:)) ?? .voz
        recordingShortcut = defaults.data(forKey: "recordingShortcut")
            .flatMap { try? JSONDecoder().decode(RecordingShortcut.self, from: $0) }
            .flatMap { $0.validationError == nil ? $0 : nil } ?? .default
        loadHistory()
    }

    private func loadHistory() {
        guard let data = try? Data(contentsOf: historyURL) else { return }
        if let memos = try? JSONDecoder().decode([Memo].self, from: data) {
            transcriptHistory = memos
        } else if let texts = try? JSONDecoder().decode([String].self, from: data) {
            // Earlier versions stored bare strings. Assign IDs once and save
            // them, so each memo keeps the same ID across launches.
            transcriptHistory = texts.map { Memo(text: $0) }
            saveHistory()
        }
    }

    func removeMemo(id: Memo.ID) {
        transcriptHistory.removeAll { $0.id == id }
        saveHistory()
    }

    func appendHistory(_ text: String) {
        transcriptHistory.insert(Memo(text: text), at: 0)
        if transcriptHistory.count > 100 {
            transcriptHistory = Array(transcriptHistory.prefix(100))
        }
        saveHistory()
    }

    private func saveHistory() {
        storage.createDirectories()
        if let data = try? JSONEncoder().encode(transcriptHistory) {
            try? data.write(to: historyURL, options: .atomic)
        }
    }
}
