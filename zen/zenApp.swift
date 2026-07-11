import SwiftUI
import AppKit
import Combine

@main
struct ZenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup("Zen") {
            ContentView()
                .environmentObject(appDelegate)
        }
        .windowStyle(.hiddenTitleBar)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let state = ZenState.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        PillPanelManager.shared.createPanel()

        HotkeyManager.shared.onToggle = {
            PillPanelManager.shared.handleHotkey()
        }
        HotkeyManager.shared.register()
    }
}
