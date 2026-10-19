import Foundation

/// Where Zen keeps memo history and transcript files. Everything lives in an
/// app-specific folder; a plain "Zen" folder would collide with other apps
/// (Zen Browser uses `zen`, and the default volume is case-insensitive).
nonisolated struct ZenStorage: Sendable {
    /// Kept fixed rather than read from the bundle so data stays put if the
    /// bundle identifier ever changes, and so standalone checks find it too.
    static let folderName = "pipper.dev.zen"

    let directory: URL
    private let legacyDirectory: URL

    var historyURL: URL { directory.appendingPathComponent("transcript_history.json") }
    var transcriptsDirectory: URL { directory.appendingPathComponent("Transcripts", isDirectory: true) }

    /// `applicationSupport` is replaceable so checks never touch real data.
    init(applicationSupport: URL? = nil) {
        let base = applicationSupport
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        legacyDirectory = base
        directory = base.appendingPathComponent(Self.folderName, isDirectory: true)
    }

    static let standard = ZenStorage()

    func createDirectories() {
        try? FileManager.default.createDirectory(at: transcriptsDirectory, withIntermediateDirectories: true)
    }

    /// Earlier versions wrote straight into Application Support. Move only
    /// files that are recognizably Zen's: a history file that decodes as memo
    /// history, and `transcript_*.txt` files from the shared "Transcripts"
    /// folder, which is a generic name another app could also use.
    func migrateLegacyData() {
        let fileManager = FileManager.default
        createDirectories()

        let legacyHistory = legacyDirectory.appendingPathComponent("transcript_history.json")
        if !fileManager.fileExists(atPath: historyURL.path),
           let data = try? Data(contentsOf: legacyHistory),
           (try? JSONDecoder().decode([String].self, from: data)) != nil {
            try? fileManager.moveItem(at: legacyHistory, to: historyURL)
        }

        let legacyTranscripts = legacyDirectory.appendingPathComponent("Transcripts", isDirectory: true)
        let names = (try? fileManager.contentsOfDirectory(atPath: legacyTranscripts.path)) ?? []
        for name in names where name.hasPrefix("transcript_") && name.hasSuffix(".txt") {
            let destination = transcriptsDirectory.appendingPathComponent(name)
            guard !fileManager.fileExists(atPath: destination.path) else { continue }
            try? fileManager.moveItem(at: legacyTranscripts.appendingPathComponent(name), to: destination)
        }
        // Remove the old folder only once nothing (not even another app's file) remains.
        if !names.isEmpty, (try? fileManager.contentsOfDirectory(atPath: legacyTranscripts.path))?
            .allSatisfy({ $0 == ".DS_Store" }) == true {
            try? fileManager.removeItem(at: legacyTranscripts)
        }
    }
}
