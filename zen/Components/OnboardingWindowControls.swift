import AppKit
import SwiftUI

/// SwiftUI's hidden title bar retains traffic lights. Hide only the controls
/// belonging to onboarding's host window, restoring them when it leaves.
struct OnboardingWindowControls: NSViewRepresentable {
    func makeNSView(context: Context) -> ControlView { ControlView() }
    func updateNSView(_ nsView: ControlView, context: Context) {}

    static func dismantleNSView(_ nsView: ControlView, coordinator: ()) {
        nsView.restoreControls()
    }

    final class ControlView: NSView {
        private weak var configuredWindow: NSWindow?
        private var previousVisibility: [(NSWindow.ButtonType, Bool)] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window !== configuredWindow else { return }
            restoreControls()
            guard let window else { return }
            configuredWindow = window
            for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                guard let button = window.standardWindowButton(type) else { continue }
                previousVisibility.append((type, button.isHidden))
                button.isHidden = true
            }
        }

        func restoreControls() {
            for (type, wasHidden) in previousVisibility {
                configuredWindow?.standardWindowButton(type)?.isHidden = wasHidden
            }
            previousVisibility.removeAll()
            configuredWindow = nil
        }
    }
}
