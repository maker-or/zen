import SwiftUI

/// Portable per-word-crossfade: 700 ms ease-out, 70 ms stagger, 8 pt rise.
/// Each inserted word owns its entrance; navigation never waits for animation.
private struct OnboardingTextEntrance: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false
    let index: Int

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: reduceMotion || visible ? 0 : 8)
            .animation(reduceMotion
                       ? .easeOut(duration: 0.15)
                       : .timingCurve(0.16, 1, 0.3, 1, duration: 0.7).delay(Double(index) * 0.07),
                       value: visible)
            .task { visible = true }
    }
}

extension View {
    func onboardingReveal(index: Int) -> some View {
        modifier(OnboardingTextEntrance(index: index))
    }
}

struct OnboardingWordLine: View {
    let text: String
    var startingAt = 0

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(text.split(separator: " ").enumerated()), id: \.offset) { index, word in
                Text(String(word))
                    .font(.system(size: 52, weight: .regular, design: .rounded))
                    .tracking(-1.5)
                    .fixedSize()
                    .onboardingReveal(index: startingAt + index)
            }
        }
    }
}

struct OnboardingAnimatedHeading: View {
    let text: String
    private let compositionSize = CGSize(width: 800, height: 156)

    var body: some View {
        GeometryReader { geometry in
            let lines = text.components(separatedBy: "\n")
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    OnboardingWordLine(text: line,
                                       startingAt: lines.prefix(index).reduce(0) { $0 + $1.split(separator: " ").count })
                }
            }
            .frame(width: compositionSize.width, height: compositionSize.height, alignment: .topLeading)
            .scaleEffect(geometry.size.width / compositionSize.width, anchor: .topLeading)
        }
        .aspectRatio(compositionSize, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text.replacingOccurrences(of: "\n", with: " "))
        .accessibilityAddTraits(.isHeader)
    }
}
