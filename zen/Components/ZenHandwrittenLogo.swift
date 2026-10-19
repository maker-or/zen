import SwiftUI
import AppKit

/// The Zen wordmark (the app icon's handwritten "zen"), revealed as if written
/// with a pen. `progress` runs from 0 (blank) to 1 (fully written).
///
/// Each point of the logo appears when the pen reaches it along the letters'
/// centrelines, from a precomputed arrival map (Resources/ZenLogoArrival.png,
/// built by scripts/generate-logo-arrival.py), so strokes never show up early
/// where they pass close to one another.
struct ZenHandwrittenLogo: View {
    var progress: CGFloat = 1

    /// The wordmark's native size, from the source SVG's viewBox.
    static let aspectRatio: CGFloat = 210 / 128
    /// How much of the timeline the pen's soft leading edge spans.
    private static let feather: Float = 0.006
    /// Loaded from the bundle rather than the asset catalog, which would
    /// reduce the 16-bit map to 8 bits and make the pen's edge advance in steps.
    private static let arrival: Image? = Bundle.main
        .url(forResource: "ZenLogoArrival", withExtension: "png")
        .flatMap(NSImage.init(contentsOf:))
        .map(Image.init(nsImage:))

    var body: some View {
        let logo = Image("ZenLogo")
            .resizable()
            .renderingMode(.template)
            .aspectRatio(Self.aspectRatio, contentMode: .fit)
            .accessibilityLabel("Zen")
        if progress >= 1 {
            logo
        } else if progress <= 0 {
            logo.hidden()
        } else if let arrival = Self.arrival {
            // Plain values: the effect closure is Sendable and runs off the main actor.
            let progress = Float(progress), feather = Self.feather
            logo.visualEffect { content, proxy in
                content.colorEffect(ShaderLibrary.zenReveal(
                    .image(arrival), .float2(proxy.size), .float(progress), .float(feather)))
            }
        } else {
            logo.opacity(progress)   // No map: fade in rather than skip the logo.
        }
    }
}
