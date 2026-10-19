import SwiftUI

struct OnboardingShortcutHeading: View {
    @ObservedObject private var state = ZenState.shared
    private let compositionSize = CGSize(width: 800, height: 70)

    private var shortcut: RecordingShortcut { state.recordingShortcut }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 20) {
                Text("Press")
                    .onboardingReveal(index: 0)
                if !shortcut.modifierSymbols.isEmpty {
                    Text(shortcut.modifierSymbols)
                        .onboardingReveal(index: 1)
                    Text("+")
                        .onboardingReveal(index: 2)
                }
                Text(shortcut.keyName)
                    .font(.system(size: 40, weight: .regular, design: .rounded))
                    .foregroundStyle(OnboardingPalette.background)
                    .padding(.horizontal, 24)
                    .frame(minWidth: shortcut.keyName.count > 1 ? 200 : 70)
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
