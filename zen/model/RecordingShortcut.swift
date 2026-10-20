import AppKit
import Carbon.HIToolbox

/// The global record/stop shortcut, stored in the Carbon form that
/// `RegisterEventHotKey` takes: a virtual key code and a Carbon modifier mask.
nonisolated struct RecordingShortcut: Hashable, Codable, Sendable {
    let keyCode: UInt32
    let modifiers: UInt32

    static let `default` = RecordingShortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey))

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers & Self.supportedModifiers
    }

    init(keyCode: UInt16, flags: NSEvent.ModifierFlags) {
        let flags = flags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        self.init(keyCode: UInt32(keyCode), modifiers: modifiers)
    }

    private static let supportedModifiers = UInt32(controlKey | optionKey | shiftKey | cmdKey)

    var modifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        return flags
    }

    func matches(_ event: NSEvent) -> Bool {
        UInt32(event.keyCode) == keyCode
            && event.modifierFlags.intersection([.control, .option, .shift, .command]) == modifierFlags
    }

    // MARK: Single modifier keys

    /// A modifier key pressed on its own, like Right Control. Carbon can't
    /// register these, so they're watched through key events instead.
    var isModifierOnly: Bool { modifiers == 0 && Self.soloModifierKeyCodes.contains(Int(keyCode)) }

    /// The right-hand modifiers and fn: the left ones start too many other shortcuts.
    static let soloModifierKeyCodes: Set<Int> = [
        kVK_RightControl, kVK_RightOption, kVK_RightCommand, kVK_RightShift, kVK_Function
    ]

    static func isModifierKey(_ keyCode: UInt16) -> Bool { modifierKeyCodes.contains(Int(keyCode)) }

    /// Whether the modifier key a `flagsChanged` event is about went down. The
    /// device-dependent bits tell the left and right keys apart.
    static func isModifierKeyDown(_ keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        let masks: [Int: UInt] = [
            kVK_Control: 0x0001, kVK_Shift: 0x0002, kVK_RightShift: 0x0004, kVK_Command: 0x0008,
            kVK_RightCommand: 0x0010, kVK_Option: 0x0020, kVK_RightOption: 0x0040, kVK_RightControl: 0x2000,
        ]
        if Int(keyCode) == kVK_Function { return flags.contains(.function) }
        if Int(keyCode) == kVK_CapsLock { return flags.contains(.capsLock) }
        guard let mask = masks[Int(keyCode)] else { return false }
        return flags.rawValue & mask != 0
    }

    // MARK: Display

    /// Modifier symbols in the order macOS menus use: ⌃⌥⇧⌘.
    var modifierSymbols: String {
        [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")]
            .filter { modifiers & UInt32($0.0) != 0 }
            .map(\.1).joined()
    }

    var keyName: String {
        Self.specialKeyNames[Int(keyCode)] ?? Self.layoutCharacter(for: keyCode) ?? "Key \(keyCode)"
    }

    /// Compact form for buttons and hints, e.g. "⌥ Space" or "⌃⇧ R".
    var displayString: String {
        modifierSymbols.isEmpty ? keyName : "\(modifierSymbols) \(keyName)"
    }

    /// Spelled-out form for sentences and VoiceOver, e.g. "Option + Space".
    var spokenDescription: String {
        let names = [(controlKey, "Control"), (optionKey, "Option"), (shiftKey, "Shift"), (cmdKey, "Command")]
            .filter { modifiers & UInt32($0.0) != 0 }
            .map(\.1)
        return (names + [keyName]).joined(separator: " + ")
    }

    // MARK: Validation

    /// Why this shortcut can't be used, or nil when it can.
    var validationError: String? {
        if Self.modifierKeyCodes.contains(Int(keyCode)) {
            if isModifierOnly { return nil }
            return modifiers == 0
                ? "Use Right Control, Right Option, Right Command, Right Shift or fn on its own. The left keys are part of other shortcuts."
                : "Add a key to go with the modifiers."
        }
        let hasPrimaryModifier = modifiers & UInt32(controlKey | optionKey | cmdKey) != 0
        if !hasPrimaryModifier && !Self.functionKeyCodes.contains(Int(keyCode)) {
            // A bare or Shift-only key would stop that character from being typed anywhere.
            return "Include Control, Option or Command, or use a function key."
        }
        if let reason = Self.reservedShortcuts[self] {
            return "\(displayString) is used by \(reason). Choose another shortcut."
        }
        return nil
    }

    private static let functionKeyCodes: Set<Int> = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20
    ]

    private static let modifierKeyCodes: Set<Int> = [
        kVK_Command, kVK_RightCommand, kVK_Shift, kVK_RightShift, kVK_Option, kVK_RightOption,
        kVK_Control, kVK_RightControl, kVK_CapsLock, kVK_Function
    ]

    /// A global hotkey takes priority over every app, so these would break
    /// standard editing, macOS features, or Zen's own ⌘V automatic paste.
    private static let reservedShortcuts: [RecordingShortcut: String] = {
        let command = UInt32(cmdKey), shiftCommand = UInt32(cmdKey | shiftKey)
        let control = UInt32(controlKey), optionCommand = UInt32(cmdKey | optionKey)
        var reserved: [RecordingShortcut: String] = [
            RecordingShortcut(keyCode: UInt32(kVK_ANSI_V), modifiers: command): "Paste and Zen’s automatic paste",
            RecordingShortcut(keyCode: UInt32(kVK_Space), modifiers: command): "Spotlight",
            RecordingShortcut(keyCode: UInt32(kVK_Space), modifiers: control): "input source switching",
            RecordingShortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey | controlKey)): "the Character Viewer",
            RecordingShortcut(keyCode: UInt32(kVK_Tab), modifiers: command): "the app switcher",
            RecordingShortcut(keyCode: UInt32(kVK_Escape), modifiers: optionCommand): "Force Quit",
        ]
        let editing: [(Int, String)] = [
            (kVK_ANSI_A, "Select All"), (kVK_ANSI_C, "Copy"), (kVK_ANSI_X, "Cut"), (kVK_ANSI_Z, "Undo"),
            (kVK_ANSI_S, "Save"), (kVK_ANSI_Q, "Quit"), (kVK_ANSI_W, "Close Window"), (kVK_ANSI_H, "Hide"),
            (kVK_ANSI_M, "Minimize"), (kVK_ANSI_N, "New"), (kVK_ANSI_O, "Open"), (kVK_ANSI_P, "Print"),
            (kVK_ANSI_F, "Find"), (kVK_ANSI_T, "New Tab"), (kVK_ANSI_Comma, "Settings"), (kVK_ANSI_Grave, "window switching"),
        ]
        for (key, name) in editing { reserved[RecordingShortcut(keyCode: UInt32(key), modifiers: command)] = name }
        reserved[RecordingShortcut(keyCode: UInt32(kVK_ANSI_Z), modifiers: shiftCommand)] = "Redo"
        for key in [kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5] {
            reserved[RecordingShortcut(keyCode: UInt32(key), modifiers: shiftCommand)] = "screenshots"
        }
        return reserved
    }()

    private static let specialKeyNames: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "Return", kVK_ANSI_KeypadEnter: "Enter", kVK_Tab: "Tab",
        kVK_Delete: "Delete", kVK_ForwardDelete: "⌦", kVK_Escape: "Esc",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "Home", kVK_End: "End", kVK_PageUp: "Page Up", kVK_PageDown: "Page Down", kVK_Help: "Help",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18",
        kVK_F19: "F19", kVK_F20: "F20",
        kVK_RightControl: "Right Control", kVK_RightOption: "Right Option", kVK_RightCommand: "Right Command",
        kVK_RightShift: "Right Shift", kVK_Function: "fn",
    ]

    /// The unmodified character this key produces on the current keyboard
    /// layout, so the name matches the keycap (e.g. "Z" on QWERTZ).
    private static func layoutCharacter(for keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let data = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(data).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = layoutData.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return -1 }
            return UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                                  UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                  &deadKeyState, characters.count, &length, &characters)
        }
        guard status == noErr, length > 0 else { return nil }
        let text = String(utf16CodeUnits: characters, count: length)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        return text.isEmpty ? nil : text.uppercased()
    }
}
