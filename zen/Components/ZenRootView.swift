import SwiftUI

struct ZenRootView: View {
    @EnvironmentObject private var appDelegate: AppDelegate
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var state = ZenState.shared

    private var showingOnboarding: Bool {
        !state.hasCompletedOnboarding || appDelegate.demoOnboardingSessionID != nil
    }

    var body: some View {
        let demoSessionID = appDelegate.demoOnboardingSessionID
        ZStack {
            if showingOnboarding {
                if appDelegate.isDemoIntroPlaying {
                    OnboardingPalette.background
                        .frame(minWidth: 680, minHeight: 600)
                        .background(OnboardingWindowControls())
                } else {
                    OnboardingView {
                        appDelegate.finishOnboarding()
                    }
                    .onAppear {
                        appDelegate.presentDemoOnboarding(sessionID: demoSessionID)
                    }
                    .id(demoSessionID)
                    .transition(.opacity)
                }
            } else {
                ContentView().transition(.opacity)
            }
        }
        .animation(showingOnboarding ? nil : .easeInOut(duration: reduceMotion ? 0.15 : 0.45),
                   value: showingOnboarding)
        .background(MainWindowRegistration { window in
            appDelegate.registerMainWindow(window, openWindow: openWindow)
        })
    }
}

/// The Dock's AppKit action reuses a visible main window, or opens a SwiftUI
/// scene when all main windows have been closed.
private struct MainWindowRegistration: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> RegistrationView {
        let view = RegistrationView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ nsView: RegistrationView, context: Context) {
        nsView.onWindow = onWindow
        if let window = nsView.window { onWindow(window) }
    }

    final class RegistrationView: NSView {
        var onWindow: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onWindow?(window) }
        }
    }
}
