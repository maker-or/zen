import Foundation
import SwiftUI
import Combine

/// Where the recording widget sits, centered on the active screen.
enum WidgetPosition: String, CaseIterable, Identifiable {
    case top, bottom
    var id: Self { self }
    var title: String { self == .top ? "Top" : "Bottom" }
}

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

    /// Onboarding's burgundy (`OnboardingPalette.background`), so the app
    /// opens in the same color its introduction ends on.
    static let defaultThemeHex = "330000"

    @Published var themeHex: String = ZenState.defaultThemeHex {
        didSet { defaults.set(themeHex, forKey: "themeHex") }
    }
    /// Keep the small recording widget on screen between recordings.
    @Published var showsIdleWidget = true {
        didSet { defaults.set(showsIdleWidget, forKey: "showsIdleWidget") }
    }
    @Published var widgetPosition: WidgetPosition = .bottom {
        didSet { defaults.set(widgetPosition.rawValue, forKey: "widgetPosition") }
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
        themeHex = defaults.string(forKey: "themeHex") ?? (isDarkMode ? "191919" : Self.defaultThemeHex)
        transcriptionModel = defaults.string(forKey: "transcriptionModel")
            .flatMap(TranscriptionModel.init(rawValue:)) ?? .voz
        showsIdleWidget = defaults.object(forKey: "showsIdleWidget") as? Bool ?? true
        widgetPosition = defaults.string(forKey: "widgetPosition").flatMap(WidgetPosition.init(rawValue:)) ?? .bottom
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
