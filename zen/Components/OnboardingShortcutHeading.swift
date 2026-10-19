import SwiftUI

struct OnboardingShortcutHeading: View {
    @ObservedObject private var state = ZenState.shared
    @ObservedObject private var capture = ShortcutCapture.shared
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
                    .background(OnboardingPalette.foreground, in: .rect(cornerRadius: 7))
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
