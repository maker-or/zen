import SwiftUI

/// Keep the inline symbols and the two-line headline together as the window scales.
struct OnboardingOpening: View {
    private let compositionSize = CGSize(width: 800, height: 156)

    var body: some View {
        GeometryReader { geometry in
            composition
                .frame(width: compositionSize.width, height: compositionSize.height, alignment: .topLeading)
                .scaleEffect(geometry.size.width / compositionSize.width, anchor: .topLeading)
        }
        .aspectRatio(compositionSize, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Type at the speed of your thoughts")
        .accessibilityAddTraits(.isHeader)
    }

    private var composition: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 11) {
                word("Type")
                    .onboardingReveal(index: 0)
                spaceKey
                    .onboardingReveal(index: 1)
                OnboardingWordLine(text: "at the speed", startingAt: 2)
                Image(systemName: "bolt.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(OnboardingPalette.accent)
                    .padding(.leading, -10)
                    .onboardingReveal(index: 5)
            }
            HStack(spacing: 22) {
                OnboardingWordLine(text: "of your thoughts", startingAt: 6)
                Image("OnboardingBird")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 60, height: 44)
                    .rotationEffect(.degrees(-15))
                    .onboardingReveal(index: 9)
            }
        }
    }

    private func word(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 52, weight: .regular, design: .rounded))
            .tracking(-1.5)
            .fixedSize()
    }

    private var spaceKey: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(OnboardingPalette.accent)
            .frame(width: 46, height: 31)
            .overlay(alignment: .bottom) {
                Capsule()
                    .fill(.black)
                    .frame(width: 23, height: 3.5)
                    .padding(.bottom, 4)
            }
    }
}

#Preview {
    OnboardingOpening()
        .foregroundStyle(OnboardingPalette.foreground)
        .padding(56)
        .background(OnboardingPalette.background)
        .frame(width: 960)
}
