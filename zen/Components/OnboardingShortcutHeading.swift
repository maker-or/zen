import SwiftUI

struct OnboardingShortcutHeading: View {
    @ObservedObject private var state = ZenState.shared
    @ObservedObject private var capture = ShortcutCapture.shared
    @ObservedObject private var presses = ShortcutPressMonitor.shared
    private let compositionSize = CGSize(width: 800, height: 70)

    private var shortcut: RecordingShortcut { state.recordingShortcut }
    // While a new shortcut is being chosen, follow the keys as they're held.
    private var modifierSymbols: String { capture.isCapturing ? capture.heldSymbols : shortcut.modifierSymbols }
    private var keyName: String { capture.isCapturing ? "…" : shortcut.keyName }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 20) {
                Text("Press")
                    .onboardingReveal(index: 0)
                if !modifierSymbols.isEmpty {
                    Text(modifierSymbols)
                        .foregroundStyle(presses.isPressed ? OnboardingPalette.accent : OnboardingPalette.foreground)
                        .onboardingReveal(index: 1)
                    Text("+")
                        .onboardingReveal(index: 2)
                }
                Text(keyName)
                    .font(.system(size: 40, weight: .regular, design: .rounded))
                    .foregroundStyle(OnboardingPalette.background)
                    .padding(.horizontal, 24)
                    .frame(minWidth: keyName.count > 1 ? 200 : 70)
                    .frame(height: 49)
                    // The keycap goes down and lights up while the shortcut is held.
                    .background(presses.isPressed ? OnboardingPalette.accent : OnboardingPalette.foreground,
                                in: .rect(cornerRadius: 7))
                    .scaleEffect(presses.isPressed ? 0.93 : 1)
                    .animation(.spring(duration: 0.18), value: presses.isPressed)
                    .onboardingReveal(index: 3)
            }
            .id(shortcut)
            .font(.system(size: 52, weight: .regular, design: .rounded))
            .tracking(-1.5)
            .fixedSize()
            .frame(width: compositionSize.width, height: compositionSize.height, alignment: .topLeading)
            .scaleEffect(geometry.size.width / compositionSize.width, anchor: .topLeading)
        }
        .aspectRatio(compositionSize, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Press \(shortcut.spokenDescription)")
        .accessibilityAddTraits(.isHeader)
    }
}

/// Below the shortcut: asks to try it, then confirms it works.
struct OnboardingShortcutCheck: View {
    @ObservedObject private var state = ZenState.shared
    @ObservedObject private var capture = ShortcutCapture.shared
    @ObservedObject private var presses = ShortcutPressMonitor.shared
    @ObservedObject private var autoPaste = AutoPasteService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !capture.isCapturing {
                if presses.hasWorked {
                    Label("It works. Use it in any app once you open Zen.",
                          systemImage: "checkmark.circle.fill")
                        .foregroundStyle(OnboardingPalette.accent)
                        .transition(.opacity)
                } else {
                    Label("Try it now", systemImage: "keyboard")
                        .foregroundStyle(OnboardingPalette.secondary)
                }
                // Skipped on the paste step; a lone modifier needs it to work elsewhere.
                if state.recordingShortcut.isModifierOnly && !autoPaste.isTrusted {
                    Text("\(state.recordingShortcut.keyName) needs automatic paste turned on to work in other apps.")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(OnboardingPalette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(.system(size: 15, weight: .medium, design: .rounded))
        .animation(.easeOut(duration: 0.2), value: presses.hasWorked)
        .onAppear { presses.start() }
        .onDisappear { presses.stop() }
    }
}
