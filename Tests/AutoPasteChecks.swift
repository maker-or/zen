import AppKit
import ApplicationServices

@MainActor
private final class FakePasteAccess: PasteAccess {
    var isTrusted = true
    var focus: PasteDestination?
    var pasteCount = 0
    var canPost = true
    func focusedInput() -> PasteDestination? { focus }
    func postPaste(to destination: PasteDestination) -> Bool {
        precondition(destination == focus, "Paste must target the validated input's process")
        pasteCount += 1
        return canPost
    }
}

@main
@MainActor
struct AutoPasteChecks {
    static func main() async {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let driver = FakePasteAccess()
        let service = AutoPasteService(access: driver, pasteboard: board)
        let original = PasteDestination(processID: 123, element: AXUIElementCreateApplication(123))
        let otherField = PasteDestination(processID: 123, element: AXUIElementCreateSystemWide())
        let otherApp = PasteDestination(processID: 456, element: AXUIElementCreateApplication(456))
        let text = "A transcript ready for the insertion point."
        func copy(_ value: String = text) {
            board.clearContents()
            board.setString(value, forType: .string)
        }
        func capture() {
            driver.focus = original
            driver.isTrusted = true
            service.captureDestination(enabled: true)
            copy()
        }
        func check(_ result: Bool, _ message: String = "Paste check failed") { precondition(result, message) }
        func expectFallback(_ message: String) async {
            let before = driver.pasteCount
            check(!(await service.pasteIfPossible(text, enabled: true)), message)
            precondition(driver.pasteCount == before && board.string(forType: .string) == text,
                         "Fallback must retain the clipboard without posting a shortcut")
        }

        capture()
        check(await service.pasteIfPossible(text, enabled: true))
        precondition(driver.pasteCount == 1)
        check(!(await service.pasteIfPossible(text, enabled: true)), "A result must not be pasted twice")
        print("PASS: same focused input receives one paste; clipboard retained")

        let terminal = PasteInputCapabilities(role: kAXTextAreaRole as String, hasTextSelection: true)
        precondition(terminal.acceptsPaste, "A text editor need not expose a writable AX value to accept keyboard paste")
        precondition(PasteInputCapabilities(role: kAXTextFieldRole as String, hasTextSelection: true).acceptsPaste,
                     "An insertion point without selected text must accept paste")
        precondition(PasteInputCapabilities(role: kAXGroupRole as String, isEditable: true).acceptsPaste,
                     "Custom web editors may expose an editable group")
        precondition(!PasteInputCapabilities(role: kAXTextFieldRole as String, subrole: kAXSecureTextFieldSubrole as String, hasTextSelection: true).acceptsPaste)
        precondition(!PasteInputCapabilities(role: kAXTextAreaRole as String, isEditable: false, hasTextSelection: true).acceptsPaste)
        precondition(!PasteInputCapabilities(role: kAXTextFieldRole as String, isEnabled: false, canSetValue: true).acceptsPaste)
        precondition(!PasteInputCapabilities(role: kAXButtonRole as String).acceptsPaste)
        print("PASS: selection-only terminal/web inputs accepted; password, disabled, read-only, and non-text controls rejected")

        let events = SystemPasteAccess.pasteEvents()!
        precondition(events.0.type == .keyDown && events.1.type == .keyUp)
        for event in [events.0, events.1] {
            precondition(event.getIntegerValueField(.keyboardEventKeycode) == 9)
            precondition(event.flags.contains(.maskCommand))
            precondition(!event.flags.contains(.maskAlternate) && !event.flags.contains(.maskShift))
        }
        print("PASS: native paste events use Command-V without the recording shortcut's Option modifier")

        capture(); driver.focus = nil
        await expectFallback("No focused input is a normal clipboard-only completion")
        capture(); driver.focus = otherField
        await expectFallback("Moving to another input in the same app must not receive old dictation")
        capture(); driver.focus = otherApp
        await expectFallback("Switching apps must not redirect dictation")
        driver.focus = nil
        service.captureDestination(enabled: true)
        driver.focus = original
        copy()
        await expectFallback("A field focused after recording started must not become the destination")
        print("PASS: no field, changed field, changed app, and late focus fall back to clipboard")

        capture()
        let countBeforeWaiting = driver.pasteCount
        let pendingPaste = Task { await service.pasteIfPossible(text, enabled: true) }
        try? await Task.sleep(for: .milliseconds(25))
        driver.focus = otherApp
        check(!(await pendingPaste.value), "Focus must be checked after the clipboard-settling delay")
        precondition(driver.pasteCount == countBeforeWaiting)
        precondition(service.deliveryMessage?.isEmpty == false, "Settings must explain clipboard fallback")
        print("PASS: focus changes during the paste delay are respected and reported in Settings")

        capture(); driver.isTrusted = false
        await expectFallback("Revoked permission must be respected")
        service.captureDestination(enabled: true)
        driver.isTrusted = true
        driver.focus = original
        copy()
        await expectFallback("Permission granted mid-recording must not invent a destination")
        capture()
        let before = driver.pasteCount
        check(!(await service.pasteIfPossible(text, enabled: false)))
        precondition(driver.pasteCount == before)
        service.captureDestination(enabled: false)
        copy()
        await expectFallback("Disabled capture must not deliver even if later enabled")
        print("PASS: denied/revoked permission and disabling automatic paste produce no paste events")

        capture(); copy("A newer clipboard item")
        let previous = driver.pasteCount
        check(!(await service.pasteIfPossible(text, enabled: true)))
        precondition(driver.pasteCount == previous && board.string(forType: .string) == "A newer clipboard item")
        capture(); service.discardDestination()
        await expectFallback("A failed/cancelled recording must discard its destination")
        capture(); copy("   ")
        check(!(await service.pasteIfPossible("   ", enabled: true)))
        capture(); driver.canPost = false
        check(!(await service.pasteIfPossible(text, enabled: true)))
        precondition(board.string(forType: .string) == text)
        print("PASS: clipboard replacement, cancellation, empty speech, and event failure remain safe")
    }
}
