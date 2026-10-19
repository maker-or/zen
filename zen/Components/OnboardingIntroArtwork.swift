import SwiftUI

/// These cue points also score Resources/OnboardingIntro.wav.
enum OnboardingIntroTiming {
    static let bloomEnd = 0.38
    static let expansion = 0.65
    static let windowSettled = 1.9
    /// The wordmark is written from `logo` to `logoVisible`, then held.
    static let logo = 1.55
    static let logoVisible = 3.0
    static let dissolve = 3.3
    static let logoFade = 0.45
    static let handoff = 4.25
    static let handoffFade = 0.18
    static let reducedMotionHandoff = 0.6
    static let canvasPadding: CGFloat = 72
}

/// A deterministic frame of the opening, sampled by the audio-synchronized clock.
struct OnboardingIntroArtwork: View {
    let elapsed: TimeInterval
    var reduceMotion = false

    var body: some View {
        GeometryReader { geometry in
            let padding = OnboardingIntroTiming.canvasPadding
            let target = CGSize(width: max(1, geometry.size.width - padding * 2),
                                height: max(1, geometry.size.height - padding * 2))
            let expansion = eased(OnboardingIntroTiming.expansion, OnboardingIntroTiming.windowSettled)
            let width = target.width * (reduceMotion ? 1 : 0.24 + expansion * 0.76)
            let height = target.height * (reduceMotion ? 1 : 0.4 + expansion * 0.6)
            let morph = reduceMotion ? 1 : eased(0.7, OnboardingIntroTiming.windowSettled)
            let bloom = reduceMotion ? eased(0, 0.2) : eased(0, OnboardingIntroTiming.bloomEnd)
            let wash = reduceMotion ? 0 : 1 - eased(OnboardingIntroTiming.dissolve, OnboardingIntroTiming.handoff)
            let writing = reduceMotion ? 0 : penProgress(OnboardingIntroTiming.logo, OnboardingIntroTiming.logoVisible)
            let logoOpacity = reduceMotion ? 0 : 1 - eased(OnboardingIntroTiming.dissolve,
                                                          OnboardingIntroTiming.dissolve + OnboardingIntroTiming.logoFade)
            let shape = OnboardingBloomShape(morph: morph)

            ZStack {
                shape
                    .fill(OnboardingPalette.accent.opacity(0.65))
                    .frame(width: width, height: height)
                    .blur(radius: 42)
                    .opacity(reduceMotion ? 0 : bloom * (1 - eased(1.1, 2.2)) * 0.8)

                ZStack {
                    OnboardingPalette.background
                    GeometryReader { surface in
                        ZStack {
                            LinearGradient(colors: [OnboardingPalette.foreground, Color(red: 0.48, green: 0.12, blue: 0.2), OnboardingPalette.background],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                            glow(OnboardingPalette.accent, size: surface.size, x: 0.22 + expansion * 0.12, y: 0.26, diameter: 0.95)
                            glow(Color(red: 0.72, green: 0.22, blue: 0.31), size: surface.size, x: 0.8, y: 0.35 + expansion * 0.22, diameter: 1.1)
                            glow(OnboardingPalette.secondary, size: surface.size, x: 0.6, y: 0.86, diameter: 0.8)
                        }
                    }
                    .opacity(wash)
                }
                .frame(width: width, height: height)
                .clipShape(shape)
                .overlay {
                    shape.stroke(OnboardingPalette.accent.opacity(0.2 * expansion * wash), lineWidth: 1)
                }
                .blur(radius: reduceMotion ? 0 : 30 * (1 - eased(0.2, OnboardingIntroTiming.windowSettled)))
                .opacity(bloom)
                .shadow(color: .black.opacity(0.16 * expansion), radius: 22, y: 8)

                ZenHandwrittenLogo(progress: writing)
                    .foregroundStyle(OnboardingPalette.accent)
                    .frame(width: 180)
                    .shadow(color: OnboardingPalette.background.opacity(0.3), radius: 6, y: 2)
                    .scaleEffect(0.97 + eased(OnboardingIntroTiming.logo, OnboardingIntroTiming.dissolve) * 0.03)
                    .opacity(logoOpacity)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// A pen accelerates gently and settles, rather than easing to a crawl.
    private func penProgress(_ start: Double, _ end: Double) -> CGFloat {
        let t = min(1, max(0, (elapsed - start) / (end - start)))
        let speedUp = 0.15, slowDown = 0.12
        let speed = 1 / (1 - (speedUp + slowDown) / 2)   // steady speed between the two
        if t < speedUp { return speed * t * t / (2 * speedUp) }
        if t > 1 - slowDown { return 1 - speed * (1 - t) * (1 - t) / (2 * slowDown) }
        return speed * (t - speedUp / 2)
    }

    private func eased(_ start: Double, _ end: Double) -> CGFloat {
        let progress = min(1, max(0, (elapsed - start) / (end - start)))
        return progress * progress * (3 - 2 * progress)
    }

    private func glow(_ color: Color, size: CGSize, x: CGFloat, y: CGFloat, diameter: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: [color.opacity(0.9), color.opacity(0)], center: .center,
                                 startRadius: 0, endRadius: max(size.width, size.height) * diameter / 2))
            .frame(width: max(size.width, size.height) * diameter,
                   height: max(size.width, size.height) * diameter)
            .position(x: size.width * x, y: size.height * y)
    }
}

/// Eight smooth cubic segments interpolate an organic silhouette into a window.
private struct OnboardingBloomShape: Shape {
    let morph: CGFloat

    func path(in rect: CGRect) -> Path {
        let blob: [CGPoint] = [CGPoint(x: 0.26, y: 0.08), CGPoint(x: 0.7, y: 0.1),
                               CGPoint(x: 0.94, y: 0.35), CGPoint(x: 0.85, y: 0.73),
                               CGPoint(x: 0.65, y: 0.95), CGPoint(x: 0.3, y: 0.9),
                               CGPoint(x: 0.06, y: 0.65), CGPoint(x: 0.07, y: 0.32)]
        let rx = min(0.2, 22 / max(1, rect.width))
        let ry = min(0.2, 22 / max(1, rect.height))
        let corners: [CGPoint] = [CGPoint(x: rx, y: 0), CGPoint(x: 1 - rx, y: 0),
                                  CGPoint(x: 1, y: ry), CGPoint(x: 1, y: 1 - ry),
                                  CGPoint(x: 1 - rx, y: 1), CGPoint(x: rx, y: 1),
                                  CGPoint(x: 0, y: 1 - ry), CGPoint(x: 0, y: ry)]
        let k: CGFloat = 0.55228475
        let cornerControls: [(CGPoint, CGPoint)] = [
            (CGPoint(x: rx + (1 - 2 * rx) / 3, y: 0), CGPoint(x: 1 - rx - (1 - 2 * rx) / 3, y: 0)),
            (CGPoint(x: 1 - rx + rx * k, y: 0), CGPoint(x: 1, y: ry - ry * k)),
            (CGPoint(x: 1, y: ry + (1 - 2 * ry) / 3), CGPoint(x: 1, y: 1 - ry - (1 - 2 * ry) / 3)),
            (CGPoint(x: 1, y: 1 - ry + ry * k), CGPoint(x: 1 - rx + rx * k, y: 1)),
            (CGPoint(x: 1 - rx - (1 - 2 * rx) / 3, y: 1), CGPoint(x: rx + (1 - 2 * rx) / 3, y: 1)),
            (CGPoint(x: rx - rx * k, y: 1), CGPoint(x: 0, y: 1 - ry + ry * k)),
            (CGPoint(x: 0, y: 1 - ry - (1 - 2 * ry) / 3), CGPoint(x: 0, y: ry + (1 - 2 * ry) / 3)),
            (CGPoint(x: 0, y: ry - ry * k), CGPoint(x: rx - rx * k, y: 0))
        ]
        func mix(_ first: CGPoint, _ second: CGPoint) -> CGPoint {
            CGPoint(x: rect.minX + (first.x + (second.x - first.x) * morph) * rect.width,
                    y: rect.minY + (first.y + (second.y - first.y) * morph) * rect.height)
        }
        var path = Path()
        path.move(to: mix(blob[0], corners[0]))
        for index in 0..<8 {
            let previous = blob[(index + 7) % 8]
            let start = blob[index]
            let end = blob[(index + 1) % 8]
            let next = blob[(index + 2) % 8]
            let first = CGPoint(x: start.x + (end.x - previous.x) / 6, y: start.y + (end.y - previous.y) / 6)
            let second = CGPoint(x: end.x - (next.x - start.x) / 6, y: end.y - (next.y - start.y) / 6)
            path.addCurve(to: mix(end, corners[(index + 1) % 8]),
                          control1: mix(first, cornerControls[index].0),
                          control2: mix(second, cornerControls[index].1))
        }
        path.closeSubpath()
        return path
    }
}
