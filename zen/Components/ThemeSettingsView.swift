import SwiftUI
import AppKit

struct ZenTheme {
    let hex: String

    private var rgb: (Double, Double, Double) {
        let value = UInt32(hex, radix: 16) ?? 0xF5F3EF
        return (Double((value >> 16) & 255) / 255, Double((value >> 8) & 255) / 255, Double(value & 255) / 255)
    }
    var background: Color { Color(red: rgb.0, green: rgb.1, blue: rgb.2) }
    private var luminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(rgb.0) + 0.7152 * linear(rgb.1) + 0.0722 * linear(rgb.2)
    }
    var isDark: Bool { luminance < 0.179 }
    var foreground: Color {
        // Keep the hue and saturation, changing lightness for legible text.
        let maximum = max(rgb.0, rgb.1, rgb.2)
        let minimum = min(rgb.0, rgb.1, rgb.2)
        let delta = maximum - minimum
        let lightness = (maximum + minimum) / 2
        let saturation = delta == 0 ? 0 : delta / (1 - abs(2 * lightness - 1))
        let hue: Double
        if delta == 0 { hue = 0 }
        else if maximum == rgb.0 { hue = ((rgb.1 - rgb.2) / delta).truncatingRemainder(dividingBy: 6) / 6 }
        else if maximum == rgb.1 { hue = ((rgb.2 - rgb.0) / delta + 2) / 6 }
        else { hue = ((rgb.0 - rgb.1) / delta + 4) / 6 }
        let normalizedHue = hue < 0 ? hue + 1 : hue
        let backgroundLuminance = luminance
        for step in 0...100 {
            let l = isDark ? 0.84 + Double(step) * 0.0016 : 0.22 - Double(step) * 0.0022
            let chroma = (1 - abs(2 * l - 1)) * saturation
            let x = chroma * (1 - abs((normalizedHue * 6).truncatingRemainder(dividingBy: 2) - 1))
            let m = l - chroma / 2
            let channels: (Double, Double, Double)
            switch normalizedHue * 6 {
            case ..<1: channels = (chroma, x, 0)
            case ..<2: channels = (x, chroma, 0)
            case ..<3: channels = (0, chroma, x)
            case ..<4: channels = (0, x, chroma)
            case ..<5: channels = (x, 0, chroma)
            default: channels = (chroma, 0, x)
            }
            let r = channels.0 + m, g = channels.1 + m, b = channels.2 + m
            func linear(_ c: Double) -> Double {
                c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            let textLuminance = 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
            let contrast = (max(textLuminance, backgroundLuminance) + 0.05) / (min(textLuminance, backgroundLuminance) + 0.05)
            if contrast >= 4.5 { return Color(red: r, green: g, blue: b) }
        }
        return isDark ? .white : .black
    }
    var surface: Color { background }
}

private struct ZenThemeKey: EnvironmentKey {
    static let defaultValue = ZenTheme(hex: "F5F3EF")
}
extension EnvironmentValues {
    var zenTheme: ZenTheme {
        get { self[ZenThemeKey.self] }
        set { self[ZenThemeKey.self] = newValue }
    }
}

struct ThemeSettingsView: View {
    @ObservedObject var state: ZenState
    @State private var hue = 0.6
    @State private var saturation = 0.5
    @State private var brightness = 0.8
    private var theme: ZenTheme { ZenTheme(hex: state.themeHex) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Appearance").font(.title3.weight(.semibold))
            GeometryReader { geometry in
                ZStack {
                    Color(hue: hue, saturation: 1, brightness: 1)
                    LinearGradient(colors: [.white, .clear], startPoint: .leading, endPoint: .trailing)
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    Circle().fill(theme.background).frame(width: 18, height: 18)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .shadow(color: .black.opacity(0.6), radius: 2)
                        .position(x: max(9, min(geometry.size.width - 9, saturation * geometry.size.width)),
                                  y: max(9, min(geometry.size.height - 9, (1 - brightness) * geometry.size.height)))
                }
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    saturation = min(1, max(0, value.location.x / geometry.size.width))
                    brightness = 1 - min(1, max(0, value.location.y / geometry.size.height))
                    updateColor()
                })
                .accessibilityLabel("Saturation and brightness")
            }
            .frame(height: 165)
            HueSlider(value: $hue) { updateColor() }
        }
        .foregroundStyle(.primary)
        .tint(.primary)
        .padding(22)
        .frame(width: 340)
        .onAppear(perform: syncPicker)
    }

    private func syncPicker() {
        let color = NSColor(theme.background).usingColorSpace(.deviceRGB)!
        hue = color.hueComponent
        saturation = color.saturationComponent
        brightness = color.brightnessComponent
    }
    private func updateColor() {
        let color = NSColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1)
        state.themeHex = String(format: "%02X%02X%02X", Int((color.redComponent * 255).rounded()), Int((color.greenComponent * 255).rounded()), Int((color.blueComponent * 255).rounded()))
    }
}

/// A single rainbow track; a native Slider would draw its own track over it.
private struct HueSlider: View {
    @Binding var value: Double
    let onChange: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let travel = max(1, geometry.size.width - 24)
            ZStack(alignment: .leading) {
                LinearGradient(colors: (0...12).map {
                    Color(hue: Double($0) / 12, saturation: 1, brightness: 1)
                }, startPoint: .leading, endPoint: .trailing)
                    .frame(height: 14)
                    .clipShape(Capsule())
                Circle()
                    .fill(Color(hue: value, saturation: 1, brightness: 1))
                    .frame(width: 24, height: 24)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    .offset(x: value * travel)
            }
            .frame(height: 28)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { gesture in
                value = min(1, max(0, (gesture.location.x - 12) / travel))
                onChange()
            })
        }
        .frame(height: 28)
        .accessibilityElement()
        .accessibilityLabel("Hue")
        .accessibilityValue("\(Int(value * 360)) degrees")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(1, value + 0.01)
            case .decrement: value = max(0, value - 0.01)
            @unknown default: break
            }
            onChange()
        }
        .focusable()
        .onKeyPress(.leftArrow) { value = max(0, value - 0.01); onChange(); return .handled }
        .onKeyPress(.rightArrow) { value = min(1, value + 0.01); onChange(); return .handled }
    }
}
