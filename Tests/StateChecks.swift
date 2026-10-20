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

        let rightControl = RecordingShortcut(keyCode: UInt32(kVK_RightControl), modifiers: 0)
        precondition(rightControl.validationError == nil && rightControl.isModifierOnly, "Right Control alone is a shortcut")
        precondition(rightControl.displayString == "Right Control" && rightControl.spokenDescription == "Right Control")
        precondition(RecordingShortcut(keyCode: UInt32(kVK_Function), modifiers: 0).validationError == nil, "fn alone is a shortcut")
        precondition(RecordingShortcut(keyCode: UInt32(kVK_Control), modifiers: 0).validationError != nil,
                     "Left Control alone would start with every Control shortcut")
        precondition(!RecordingShortcut.default.isModifierOnly)
        // Right Control's own device bit, not just "a Control key".
        let rightDown = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.control.rawValue | 0x2000)
        let leftDown = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.control.rawValue | 0x0001)
        precondition(RecordingShortcut.isModifierKeyDown(UInt16(kVK_RightControl), flags: rightDown))
        precondition(!RecordingShortcut.isModifierKeyDown(UInt16(kVK_RightControl), flags: leftDown),
                     "Left Control held doesn't count as Right Control")
        precondition(!RecordingShortcut.isModifierKeyDown(UInt16(kVK_RightControl), flags: []), "Released")
        precondition(RecordingShortcut.isModifierKeyDown(UInt16(kVK_Function), flags: .function))
        print("PASS: single modifier keys: right-hand keys and fn allowed, left keys rejected, left and right told apart")

        let hold = ShortcutGesture.holdThreshold, window = ShortcutGesture.doubleTapWindow
        var gesture = ShortcutGesture()
        // Hold to talk.
        precondition(gesture.press(at: 10, status: .idle) == .start)
        precondition(gesture.release(at: 10 + hold + 0.1, isRecording: true, singleKey: false) == .stop, "Releasing a hold stops")
        // A single tap of a key combination talks hands-free; the next press finishes.
        precondition(gesture.press(at: 20, status: .idle) == .start)
        precondition(gesture.release(at: 20.1, isRecording: true, singleKey: false) == .none, "A tap keeps listening")
        precondition(gesture.press(at: 25, status: .recording) == .stop, "The next press finishes")
        precondition(gesture.release(at: 25.1, isRecording: false, singleKey: false) == .none)
        // Double tap: the second tap doesn't stop it.
        precondition(gesture.press(at: 30, status: .idle) == .start)
        _ = gesture.release(at: 30.1, isRecording: true, singleKey: false)
        precondition(gesture.press(at: 30.1 + window / 2, status: .recording) == .none, "A second tap keeps listening")
        precondition(gesture.release(at: 30.4, isRecording: true, singleKey: false) == .none)
        precondition(gesture.press(at: 30.5, status: .recording) == .stop, "After a double tap, any press finishes")
        _ = gesture.release(at: 30.6, isRecording: false, singleKey: false)
        // A single key: one tap is dropped, a double tap talks hands-free.
        precondition(gesture.press(at: 40, status: .idle) == .start)
        precondition(gesture.release(at: 40.1, isRecording: true, singleKey: true) == .waitForSecondTap)
        precondition(gesture.secondTapTimedOut() == .cancel, "A stray tap of Right Control is dropped")
        precondition(gesture.press(at: 50, status: .idle) == .start)
        _ = gesture.release(at: 50.1, isRecording: true, singleKey: true)
        precondition(gesture.press(at: 50.2, status: .recording) == .none)
        precondition(gesture.secondTapTimedOut() == .none, "The second tap arrived in time")
        precondition(gesture.release(at: 50.3, isRecording: true, singleKey: true) == .none)
        precondition(gesture.press(at: 53, status: .recording) == .stop)
        _ = gesture.release(at: 53.1, isRecording: false, singleKey: true)
        // Right Control + C drops what the press started.
        precondition(gesture.press(at: 60, status: .idle) == .start)
        precondition(gesture.interrupt() == .cancel)
        precondition(gesture.release(at: 60.5, isRecording: false, singleKey: true) == .none)
        // Busy transcribing ignores the shortcut; a failed start forgets the press.
        precondition(gesture.press(at: 70, status: .busy) == .none)
        precondition(gesture.press(at: 80, status: .idle) == .start)
        precondition(gesture.release(at: 80.5, isRecording: false, singleKey: false) == .none, "No microphone: nothing to stop")
        // Hands-free left over from an ended recording doesn't swallow the next press.
        precondition(gesture.press(at: 90, status: .idle) == .start)
        _ = gesture.release(at: 90.1, isRecording: true, singleKey: false)
        precondition(gesture.press(at: 95, status: .idle) == .start, "The recording ended some other way")
        print("PASS: hold to talk, tap and double tap for hands-free, stray single-key taps and chords dropped")

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

        // An older build opened after the move saves only its new memos to the
        // old location, including identical ones. All of them must be merged.
        let legacyHistory = scratch.appendingPathComponent("transcript_history.json")
        try JSONEncoder().encode(["Read the code base.", "Read the code base.", "Uh"]).write(to: legacyHistory)
        let reopened = ZenState(defaults: defaults, storage: storage)
        precondition(reopened.transcriptHistory.map(\.text) == ["Read the code base.", "Read the code base.", "Uh", "new memo", "older memo"],
                     "Memos saved by an older build after migration must be merged, duplicates included")
        precondition(Set(reopened.transcriptHistory.map(\.id)).count == 5)
        precondition(!FileManager.default.fileExists(atPath: legacyHistory.path), "A merged legacy file is removed so it merges once")
        precondition(ZenState(defaults: defaults, storage: storage).transcriptHistory.count == 5, "Relaunching must not merge again")

        // An older build that was running during the move rewrites its whole
        // in-memory history plus new memos; only the new ones are added.
        let current = (0..<4).map { Memo(text: "memo \($0)") }
        precondition(ZenStorage.merge(legacy: ["fresh", "memo 0", "memo 1", "memo 2"], into: current).map(\.text)
                     == ["fresh", "memo 0", "memo 1", "memo 2", "memo 3"], "Overlap with existing history is not duplicated")
        precondition(ZenStorage.merge(legacy: ["memo 0", "memo 1"], into: current).map(\.id) == current.map(\.id),
                     "A legacy file with nothing new changes nothing")
        precondition(ZenStorage.merge(legacy: ["memo 0", "memo 0"], into: current).map(\.text).prefix(2) == ["memo 0", "memo 0"],
                     "Repeated texts that don't line up with existing history are new memos")
        precondition(ZenStorage.merge(legacy: (0..<100).map { "new \($0)" }, into: current).count == 100, "History stays capped")
        print("PASS: memos an older build saves after migration are merged once, without duplicating overlap")

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

        precondition(state.showsIdleWidget && state.widgetPosition == .bottom, "The small widget waits at the bottom by default")
        state.showsIdleWidget = false
        state.widgetPosition = .top
        let relaunched = ZenState(defaults: defaults, storage: storage)
        precondition(!relaunched.showsIdleWidget && relaunched.widgetPosition == .top, "Widget settings survive relaunch")
        precondition(state.themeHex == ZenState.defaultThemeHex && ZenState.defaultThemeHex == "330000",
                     "New installations open in onboarding's burgundy")
        print("PASS: widget visibility, position and theme defaults")
    }
}
