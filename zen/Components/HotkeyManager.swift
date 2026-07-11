import Cocoa

@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()

    var onToggle: (() -> Void)?

    private var monitor: Any?

    func register() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains(.option) &&
               event.charactersIgnoringModifiers == " " {
                self?.onToggle?()
                return nil
            }
            return event
        }
    }

    func unregister() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    deinit {
        if let monitor = self.monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
