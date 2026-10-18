import Cocoa
import Carbon

@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()

    var onToggle: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var localMonitor: Any?
    private let signature: OSType = 0x5A454E21 // "ZEN!"
    private var lastTriggerUptime: TimeInterval = 0

    func triggerToggle() {
        let now = ProcessInfo.processInfo.systemUptime
        // Debounce by 350ms to prevent duplicate triggers between Carbon and NSEvent
        guard now - lastTriggerUptime > 0.35 else { return }
        lastTriggerUptime = now
        print("[Hotkey] Triggering hotkey toggle")
        onToggle?()
    }

    func register() {
        unregister()

        // 1. Carbon Global Hotkey (interception across all applications, no accessibility permission needed)
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handler: EventHandlerUPP = { _, event, _ in
            guard let event else { return noErr }
            var hkID = EventHotKeyID()
            let err = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hkID
            )
            if err == noErr && hkID.signature == 0x5A454E21 && hkID.id == 1 {
                print("[Hotkey] Option+Space pressed globally via Carbon")
                DispatchQueue.main.async {
                    HotkeyManager.shared.triggerToggle()
                }
            }
            return noErr
        }

        let dispatcherTarget = GetEventDispatcherTarget()

        let installStatus = InstallEventHandler(
            dispatcherTarget,
            handler,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )

        if installStatus != noErr {
            print("[Hotkey] Failed to install event handler (error \(installStatus))")
        }

        let hotKeyID = EventHotKeyID(signature: signature, id: 1)
        let regStatus = RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(optionKey),
            hotKeyID,
            dispatcherTarget,
            0,
            &hotKeyRef
        )

        if regStatus != noErr {
            print("[Hotkey] Failed to register Option+Space (error \(regStatus))")
        } else {
            print("[Hotkey] Successfully registered Option+Space as global hotkey")
        }

        // 2. Local NSEvent monitor (fallback when Zen itself is active/focused)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if modifiers == .option && event.keyCode == UInt16(kVK_Space) {
                print("[Hotkey] Option+Space detected via local NSEvent monitor")
                self?.triggerToggle()
                return nil
            }
            return event
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }
}

