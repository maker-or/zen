import SwiftUI

struct OnboardingWindowView: View {
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var sessionID = UUID()

    var body: some View {
        OnboardingView {
            dismissWindow(id: "onboarding")
        }
        .id(sessionID)
        .onDisappear {
            // Every replay starts at the welcome screen, including after ⌘W.
            sessionID = UUID()
        }
    }
}
