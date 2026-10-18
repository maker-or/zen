import SwiftUI

struct OnboardingShortcutHeading: View {
    private let compositionSize = CGSize(width: 800, height: 70)

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 20) {
                Text("Press")
                    .onboardingReveal(index: 0)
                Text("⌥")
                    .onboardingReveal(index: 1)
                Text("+")
                    .onboardingReveal(index: 2)
                Text("Space")
                    .font(.system(size: 40, weight: .regular, design: .rounded))
                    .foregroundStyle(OnboardingPalette.background)
                    .frame(width: 200, height: 49)
                    .background(OnboardingPalette.foreground, in: .rect(cornerRadius: 7))
                    .onboardingReveal(index: 3)
            }
            .font(.system(size: 52, weight: .regular, design: .rounded))
            .tracking(-1.5)
            .fixedSize()
            .frame(width: compositionSize.width, height: compositionSize.height, alignment: .topLeading)
            .scaleEffect(geometry.size.width / compositionSize.width, anchor: .topLeading)
        }
        .aspectRatio(compositionSize, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Press Option + Space")
        .accessibilityAddTraits(.isHeader)
    }
}
