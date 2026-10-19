import AppKit
import Carbon.HIToolbox

/// Shortcut validation/persistence, memo history and storage migration,
/// without registering hotkeys or touching the real Application Support folder.
@main
@MainActor
struct StateChecks {
    static func main() throws {
        setbuf(stdout, nil)
        let option = UInt32(optionKey), command = UInt32(cmdKey)
        let shiftCommand = UInt32(cmdKey | shiftKey), controlOption = UInt32(controlKey | optionKey)

        let standard = RecordingShortcut.default
        precondition(standard.validationError == nil)
        precondition(standard.displayString == "⌥ Space" && standard.spokenDescription == "Option + Space")
        precondition(standard.modifierFlags == .option)

        let fromEvent = RecordingShortcut(keyCode: UInt16(kVK_ANSI_R), flags: [.control, .option, .capsLock, .numericPad])
        precondition(fromEvent == RecordingShortcut(keyCode: UInt32(kVK_ANSI_R), modifiers: controlOption),
                     "Only Control, Option, Shift and Command are part of a shortcut")
        precondition(fromEvent.modifierSymbols == "⌃⌥", "Symbols follow macOS menu order")
        precondition(RecordingShortcut(keyCode: UInt32(kVK_F5), modifiers: 0).validationError == nil,
                     "A bare function key is allowed")
        precondition(RecordingShortcut(keyCode: UInt32(kVK_F5), modifiers: 0).displayString == "F5")
        precondition(RecordingShortcut(keyCode: UInt32(kVK_ANSI_D), modifiers: 0).validationError != nil,
                     "A bare letter would block typing it")
        precondition(RecordingShortcut(keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(shiftKey)).validationError != nil,
                     "Shift alone would block typing capitals")
        precondition(RecordingShortcut(keyCode: UInt32(kVK_ANSI_V), modifiers: command).validationError != nil,
                     "⌘V is Zen's own automatic paste")
        precondition(RecordingShortcut(keyCode: UInt32(kVK_Space), modifiers: command).validationError != nil,
                     "⌘Space belongs to Spotlight")
        precondition(RecordingShortcut(keyCode: UInt32(kVK_ANSI_4), modifiers: shiftCommand).validationError != nil,
                     "Screenshot shortcuts are reserved")
        precondition(RecordingShortcut(keyCode: UInt32(kVK_Option), modifiers: option).validationError != nil,
                     "A modifier on its own is not a shortcut")
        precondition(RecordingShortcut(keyCode: UInt32(kVK_ANSI_D), modifiers: controlOption).validationError == nil)
        print("PASS: shortcut conversion, display, validation, reserved combinations")

        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("zen-state-checks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let suiteName = "ZenStateChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Legacy layout: history and transcripts straight in Application Support,
        // next to another app's file in the shared "Transcripts" folder.
        let legacyTranscripts = scratch.appendingPathComponent("Transcripts")
        try FileManager.default.createDirectory(at: legacyTranscripts, withIntermediateDirectories: true)
        try JSONEncoder().encode(["older memo"]).write(to: scratch.appendingPathComponent("transcript_history.json"))
        try "older memo".write(to: legacyTranscripts.appendingPathComponent("transcript_2026.txt"), atomically: true, encoding: .utf8)
        try "not ours".write(to: legacyTranscripts.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)

        let storage = ZenStorage(applicationSupport: scratch)
        let state = ZenState(defaults: defaults, storage: storage)
        precondition(state.transcriptHistory.map(\.text) == ["older memo"], "Existing memo history must survive the move")
        let migratedID = state.transcriptHistory[0].id
        precondition(ZenState(defaults: defaults, storage: storage).transcriptHistory.map(\.id) == [migratedID],
                     "IDs assigned to older string-only history must be saved and stay stable")
        precondition(storage.directory.lastPathComponent == "pipper.dev.zen")
        precondition(FileManager.default.fileExists(atPath: storage.transcriptsDirectory.appendingPathComponent("transcript_2026.txt").path))
        precondition(!FileManager.default.fileExists(atPath: scratch.appendingPathComponent("transcript_history.json").path))
        precondition(FileManager.default.fileExists(atPath: legacyTranscripts.appendingPathComponent("notes.txt").path),
                     "Files that aren't Zen's must stay where they are")
        state.appendHistory("new memo")
        precondition(ZenState(defaults: defaults, storage: storage).transcriptHistory.map(\.text) == ["new memo", "older memo"])
        print("PASS: history and transcripts move into the app folder, other apps' files untouched")

        // Identical memos: deleting one must remove exactly that one.
        state.appendHistory("Hi, hello.")
        state.appendHistory("between")
        state.appendHistory("Hi, hello.")
        let duplicates = state.transcriptHistory.filter { $0.text == "Hi, hello." }
        precondition(duplicates.count == 2 && duplicates[0].id != duplicates[1].id, "Identical memos need distinct IDs")
        let older = duplicates[1]
        state.removeMemo(id: older.id)
        precondition(state.transcriptHistory.map(\.text) == ["Hi, hello.", "between", "new memo", "older memo"],
                     "Deleting the older duplicate must keep the newer one in place")
        precondition(state.transcriptHistory[0].id == duplicates[0].id, "The memo that wasn't clicked must survive")
        precondition(!ZenState(defaults: defaults, storage: storage).transcriptHistory.contains { $0.id == older.id },
                     "The deletion must persist")
        state.removeMemo(id: UUID())
        precondition(state.transcriptHistory.count == 4, "Deleting an unknown ID changes nothing")
        print("PASS: memos have stable IDs, and deleting a duplicate removes only the clicked memo")

        precondition(state.recordingShortcut == .default, "New installations use Option + Space")
        let custom = RecordingShortcut(keyCode: UInt32(kVK_ANSI_D), modifiers: controlOption)
        state.recordingShortcut = custom
        precondition(ZenState(defaults: defaults, storage: storage).recordingShortcut == custom, "Shortcut must survive relaunch")
        defaults.set(try JSONEncoder().encode(RecordingShortcut(keyCode: UInt32(kVK_ANSI_V), modifiers: command)),
                     forKey: "recordingShortcut")
        precondition(ZenState(defaults: defaults, storage: storage).recordingShortcut == .default,
                     "An invalid saved shortcut falls back to the default")
        print("PASS: shortcut persistence and invalid preference fallback")
    }
}
