import SwiftUI
import AppKit
import Combine

@main
struct ZenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup("Zen", id: "main") {
            ZenRootView()
                .environmentObject(appDelegate)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: appDelegate.state.hasCompletedOnboarding ? 1280 : 860,
                     height: appDelegate.state.hasCompletedOnboarding ? 820 : 660)

        Window("Onboarding", id: "onboarding") {
            OnboardingWindowView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 860, height: 660)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        Settings {
            AppSettingsView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let state = ZenState.shared
    @Published private(set) var demoOnboardingSessionID: UUID?
    @Published private(set) var isDemoIntroPlaying = false
    private let introPresenter = OnboardingIntroPresenter()
    private weak var mainWindow: NSWindow?
    private var mainWindowSizeBeforeDemo: CGSize?
    private var openMainWindow: OpenWindowAction?
    private var captureActivated = false
    private var hasFinishedLaunching = false
    private var pendingDemoRequestID: UUID?
    private var lastHandledDemoRequestID: UUID?
    private static let demoRequestNotification = Notification.Name("pipper.dev.zen.demoOnboardingRequested")

    override init() {
        super.init()
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--demo-onboarding") {
            let requestID = arguments.indices.contains(index + 1)
                ? UUID(uuidString: arguments[index + 1]) ?? UUID() : UUID()
            // Seed the first SwiftUI render before the main window exists.
            pendingDemoRequestID = requestID
            lastHandledDemoRequestID = requestID
            demoOnboardingSessionID = requestID
            isDemoIntroPlaying = true
        }
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(receiveDemoRequest(_:)),
            name: Self.demoRequestNotification, object: Bundle.main.bundleIdentifier)
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    @objc nonisolated private func receiveDemoRequest(_ notification: Notification) {
        guard let value = notification.userInfo?["requestID"] as? String,
              let requestID = UUID(uuidString: value) else { return }
        Task { @MainActor [weak self] in
            guard let self, self.lastHandledDemoRequestID != requestID else { return }
            self.lastHandledDemoRequestID = requestID
            if !self.hasFinishedLaunching || self.mainWindow == nil {
                self.pendingDemoRequestID = requestID
                self.demoOnboardingSessionID = requestID
                self.isDemoIntroPlaying = true
                self.openMainWindow?(id: "main")
            } else {
                self.startDemoOnboarding(sessionID: requestID)
            }
        }
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let item = NSMenuItem(title: "Demo Onboarding", action: #selector(showDemoOnboarding), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return menu
    }

    func registerMainWindow(_ window: NSWindow, openWindow: OpenWindowAction) {
        mainWindow = window
        openMainWindow = openWindow
        if isDemoIntroPlaying {
            window.alphaValue = 0
            window.orderOut(nil)
        }
        startPendingDemoIfReady()
    }

    private func startPendingDemoIfReady() {
        guard hasFinishedLaunching, mainWindow != nil,
              let requestID = pendingDemoRequestID else { return }
        pendingDemoRequestID = nil
        // Window registration can happen during launch. Let AppKit finish
        // launching before presenting the panel or starting its playback.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.demoOnboardingSessionID == requestID else { return }
            self.startDemoOnboarding(sessionID: requestID)
        }
    }

    @objc func showDemoOnboarding() {
        startDemoOnboarding(sessionID: UUID())
    }

    private func startDemoOnboarding(sessionID: UUID) {
        lastHandledDemoRequestID = sessionID
        if demoOnboardingSessionID == nil { mainWindowSizeBeforeDemo = mainWindow?.frame.size }
        introPresenter.cancel()
        let reuseWindow = mainWindow.map { $0.isVisible || $0.isMiniaturized || isDemoIntroPlaying } ?? false
        let screen = mainWindow?.screen ?? NSScreen.main
        mainWindow?.alphaValue = 0
        mainWindow?.orderOut(nil)
        // Demo state is session-only; keep the saved first-launch status intact.
        isDemoIntroPlaying = screen != nil
        demoOnboardingSessionID = sessionID
        if let screen {
            let preferredFrame = mainWindow.flatMap { $0.styleMask.contains(.fullScreen) ? $0.frame : nil }
            introPresenter.start(on: screen, preferredFrame: preferredFrame) { [weak self] in
                guard let self, self.demoOnboardingSessionID == sessionID else { return }
                self.isDemoIntroPlaying = false
            }
        }
        if !reuseWindow { openMainWindow?(id: "main") }
    }

    func presentDemoOnboarding(sessionID: UUID?) {
        guard let sessionID else { return }
        // Let the onboarding insertion commit before exposing a background or
        // minimized window. Its previous main-app contents must never flash.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.demoOnboardingSessionID == sessionID, !self.isDemoIntroPlaying,
                  let window = self.mainWindow else { return }
            if !window.styleMask.contains(.fullScreen), let frame = self.introPresenter.targetFrame {
                window.setFrame(frame, display: false)
            }
            window.contentView?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            window.alphaValue = 1
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
            self.introPresenter.revealOnboarding()
            NSApp.activate()
        }
    }

    func finishOnboarding() {
        if !state.hasCompletedOnboarding { state.hasCompletedOnboarding = true }
        isDemoIntroPlaying = false
        introPresenter.cancel()
        demoOnboardingSessionID = nil
        expandMainWindow()
        mainWindowSizeBeforeDemo = nil
        activateCapture()
    }

    private func expandMainWindow() {
        guard let mainWindow,
              !mainWindow.styleMask.contains(.fullScreen),
              let screen = mainWindow.screen else { return }

        let available = screen.visibleFrame
        let current = mainWindow.frame
        let size = CGSize(width: max(current.width, max(available.width * 0.92, mainWindowSizeBeforeDemo?.width ?? 0)),
                          height: max(current.height, max(available.height * 0.92, mainWindowSizeBeforeDemo?.height ?? 0)))
        guard size.width > current.width || size.height > current.height else { return }

        let frame = CGRect(x: available.midX - size.width / 2,
                           y: available.midY - size.height / 2,
                           width: size.width, height: size.height)
        mainWindow.setFrame(frame, display: true,
                            animate: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        hasFinishedLaunching = true
        startPendingDemoIfReady()
        if state.hasCompletedOnboarding, demoOnboardingSessionID == nil { activateCapture() }
    }

    /// Register the global shortcut after the introduction, once per launch.
    func activateCapture() {
        guard !captureActivated else { return }
        captureActivated = true

        Task { await TranscriptionService.shared.warmup() }

        PillPanelManager.shared.createPanel()

        HotkeyManager.shared.onToggle = {
            PillPanelManager.shared.handleHotkey()
        }
        HotkeyManager.shared.register()
    }
}
