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
        if let data = try? Data(contentsOf: legacyHistory),
           let legacyTexts = try? JSONDecoder().decode([String].self, from: data) {
            if !fileManager.fileExists(atPath: historyURL.path) {
                try? fileManager.moveItem(at: legacyHistory, to: historyURL)
            } else if let current = Self.readMemos(at: historyURL) {
                // An older build kept running, or was opened again, after the
                // move and saved new memos to the old location. Merge them in.
                let merged = Self.merge(legacy: legacyTexts, into: current)
                if let encoded = try? JSONEncoder().encode(merged),
                   (try? encoded.write(to: historyURL, options: .atomic)) != nil {
                    try? fileManager.removeItem(at: legacyHistory)
                }
            }
        }

        let legacyTranscripts = legacyDirectory.appendingPathComponent("Transcripts", isDirectory: true)
        let names = (try? fileManager.contentsOfDirectory(atPath: legacyTranscripts.path)) ?? []
        for name in names where name.hasPrefix("transcript_") && name.hasSuffix(".txt") {
            let destination = transcriptsDirectory.appendingPathComponent(name)
            guard !fileManager.fileExists(atPath: destination.path) else { continue }
            try? fileManager.moveItem(at: legacyTranscripts.appendingPathComponent(name), to: destination)
        }
        // Remove the old folder only once nothing (not even another app's file) remains.
        removeLegacyTranscriptsFolderIfEmpty(legacyTranscripts, hadFiles: !names.isEmpty)
    }

    /// Reads history in the current format, or the string-only format of
    /// earlier versions (assigning new IDs).
    static func readMemos(at url: URL) -> [Memo]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let memos = try? JSONDecoder().decode([Memo].self, from: data) { return memos }
        return (try? JSONDecoder().decode([String].self, from: data))?.map { Memo(text: $0) }
    }

    /// Legacy history is newest-first. Its newest entries were added by the
    /// older build; the rest repeats what is already here when that build had
    /// been holding the full history in memory. Keep only the new entries,
    /// matching the overlap by position since identical texts are allowed.
    static func merge(legacy: [String], into current: [Memo], limit: Int = 100) -> [Memo] {
        let currentTexts = current.map(\.text)
        let newCount = legacy.indices.first { start in
            let tail = legacy[start...]
            return tail.count <= currentTexts.count && currentTexts.starts(with: tail)
        } ?? legacy.count
        let added = legacy.prefix(newCount).map { Memo(text: $0) }
        return Array((added + current).prefix(limit))
    }

    private func removeLegacyTranscriptsFolderIfEmpty(_ legacyTranscripts: URL, hadFiles: Bool) {
        let fileManager = FileManager.default
        if hadFiles, (try? fileManager.contentsOfDirectory(atPath: legacyTranscripts.path))?
            .allSatisfy({ $0 == ".DS_Store" }) == true {
            try? fileManager.removeItem(at: legacyTranscripts)
        }
    }
}
