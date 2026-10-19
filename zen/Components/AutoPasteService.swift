import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine

struct PasteDestination: Equatable {
    let processID: pid_t
    let element: AXUIElement

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.processID == rhs.processID && CFEqual(lhs.element, rhs.element)
    }
}

/// Text insertion support is independent of whether AX permits replacing the
/// whole value. Terminal and web editors often expose only a selection range.
struct PasteInputCapabilities {
    var role: String
    var subrole: String? = nil
    var isEnabled = true
    var isEditable: Bool? = nil
    var canSetValue = false
    var canSetSelectedText = false
    var hasTextSelection = false

    var acceptsPaste: Bool {
        guard isEnabled, isEditable != false, subrole != kAXSecureTextFieldSubrole as String else { return false }
        let textRole = [kAXTextFieldRole as String, kAXTextAreaRole as String, kAXComboBoxRole as String].contains(role)
        return (textRole || isEditable == true)
            && (canSetValue || canSetSelectedText || hasTextSelection || isEditable == true)
    }
}

@MainActor
protocol PasteAccess {
    var isTrusted: Bool { get }
    func focusedInput() -> PasteDestination?
    func postPaste(to destination: PasteDestination) -> Bool
}

/// Only shortcut recordings opt into delivery, and an absent destination is a normal result.
@MainActor
final class AutoPasteService: ObservableObject {
    static let shared = AutoPasteService()
    @Published private(set) var isTrusted: Bool
    @Published private(set) var deliveryMessage: String?
    private let access: any PasteAccess
    private let pasteboard: NSPasteboard
    private var destination: PasteDestination?

    init(access: (any PasteAccess)? = nil, pasteboard: NSPasteboard = .general) {
        let access = access ?? SystemPasteAccess()
        self.access = access
        self.pasteboard = pasteboard
        isTrusted = access.isTrusted
    }

    func refreshPermission() { isTrusted = access.isTrusted }

    func captureDestination(enabled: Bool) {
        refreshPermission()
        destination = enabled && isTrusted ? access.focusedInput() : nil
        deliveryMessage = !enabled ? "Automatic paste is off."
            : !isTrusted ? "Enable Accessibility for this copy of Zen to paste automatically."
            : destination == nil ? "No supported text input was focused. Your transcript will be copied."
            : nil
    }

    func discardDestination() { destination = nil }

    @discardableResult
    func pasteIfPossible(_ text: String, enabled: Bool) async -> Bool {
        let original = destination
        destination = nil // A result may be delivered only once.
        // Give the receiving app time to see the new clipboard and let the
        // recording shortcut's key-up finish before sending the native paste shortcut.
        do { try await Task.sleep(for: .milliseconds(100)) }
        catch { return false }
        refreshPermission()
        guard enabled else { deliveryMessage = "Automatic paste is off. The transcript was copied."; return false }
        guard isTrusted else { deliveryMessage = "Copied. Enable Accessibility for this copy of Zen to paste automatically."; return false }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard let original else { deliveryMessage = "Copied. No supported text input was focused when recording started."; return false }
        guard access.focusedInput() == original else { deliveryMessage = "Copied. Input focus changed while recording."; return false }
        guard pasteboard.string(forType: .string) == text else { deliveryMessage = "Paste skipped because the clipboard changed."; return false }
        let sent = access.postPaste(to: original)
        deliveryMessage = sent ? "Paste sent to the focused input. A copy remains on the clipboard."
            : "Copied. The input could not receive automatic paste."
        return sent
    }
}

@MainActor
struct SystemPasteAccess: PasteAccess {
    var isTrusted: Bool { AXIsProcessTrusted() }

    func focusedInput() -> PasteDestination? {
        guard isTrusted, let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        // Unresponsive or unsupported apps should promptly fall back to copy.
        AXUIElementSetMessagingTimeout(application, 0.2)
        var focused = attribute(kAXFocusedUIElementAttribute, on: application)
        if focused == nil {
            // Opt into accessibility in Chromium/Electron apps that create
            // their accessible text controls lazily for assistive clients.
            AXUIElementSetAttributeValue(application, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            focused = attribute(kAXFocusedUIElementAttribute, on: application)
        }
        guard let value = focused,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let element = value as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.2)
        let selection = attribute(kAXSelectedTextRangeAttribute, on: element)
        let hasTextSelection = selection.map {
            CFGetTypeID($0) == AXValueGetTypeID() && AXValueGetType($0 as! AXValue) == .cfRange
        } ?? false
        let capabilities = PasteInputCapabilities(
            role: attribute(kAXRoleAttribute, on: element) as? String ?? "",
            subrole: attribute(kAXSubroleAttribute, on: element) as? String,
            isEnabled: attribute(kAXEnabledAttribute, on: element) as? Bool ?? true,
            isEditable: attribute("AXEditable", on: element) as? Bool,
            canSetValue: isSettable(kAXValueAttribute, on: element),
            canSetSelectedText: isSettable(kAXSelectedTextAttribute, on: element),
            hasTextSelection: hasTextSelection)
        guard capabilities.acceptsPaste else { return nil }
        return PasteDestination(processID: app.processIdentifier, element: element)
    }

    func postPaste(to destination: PasteDestination) -> Bool {
        guard isTrusted, focusedInput() == destination,
              let events = Self.pasteEvents() else { return false }
        // Use the normal session event stream so native menu shortcuts and
        // Chromium editors handle this exactly like a keyboard paste.
        events.0.post(tap: .cgSessionEventTap)
        events.1.post(tap: .cgSessionEventTap)
        return true
    }

    static func pasteEvents() -> (CGEvent, CGEvent)? {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else { return nil }
        // Explicit flags prevent modifiers still held from the recording
        // shortcut (e.g. Option) from turning this into Option-Command-V.
        // Never send Return or submit forms.
        let command = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x000008)
        down.flags = command
        up.flags = command
        return (down, up)
    }

    private func attribute(_ name: String, on element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func isSettable(_ name: String, on element: AXUIElement) -> Bool {
        var result = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, name as CFString, &result) == .success && result.boolValue
    }
}
