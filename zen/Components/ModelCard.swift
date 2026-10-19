import SwiftUI

/// Colors for a model card, so Settings (memo theme) and onboarding (its own
/// palette) share one layout.
struct ModelCardPalette {
    let foreground: Color
    let secondary: Color
    let background: Color

    static let onboarding = ModelCardPalette(
        foreground: OnboardingPalette.accent, secondary: OnboardingPalette.secondary,
        background: OnboardingPalette.background)

    static func theme(_ theme: ZenTheme) -> ModelCardPalette {
        ModelCardPalette(foreground: theme.foreground, secondary: theme.foreground.opacity(0.68),
                         background: theme.background)
    }
}

/// A selectable model with its published speed, size and accuracy, and its
/// download or readiness state.
struct ModelCard: View {
    let model: TranscriptionModel
    let isSelected: Bool
    let palette: ModelCardPalette
    /// Show a Download/Retry button; onboarding uses its own primary button.
    var showsDownloadButton = true
    let select: () -> Void
    @ObservedObject private var service = TranscriptionService.shared

    private var specs: TranscriptionModel.Specs { model.specs }
    private var modelState: TranscriptionService.ModelState? { service.modelStates[model] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    Circle().strokeBorder(palette.foreground.opacity(isSelected ? 1 : 0.4), lineWidth: 1.5)
                    if isSelected { Circle().fill(palette.foreground).padding(4) }
                }
                .frame(width: 18, height: 18)
                Text(model.name).font(.system(size: 16, weight: .semibold, design: .rounded))
                    .fixedSize()
                Link(destination: specs.page) {
                    HStack(spacing: 3) {
                        Text(specs.publisher)
                        Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .bold))
                    }
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(palette.secondary)
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .fixedSize()
                .help("Open the \(model.name) model page")
                Spacer(minLength: 8)
                Text(specs.badge)
                    .lineLimit(1)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(palette.secondary)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .overlay(Capsule().strokeBorder(palette.foreground.opacity(0.25)))
                status
            }
            if !model.isSupported {
                Text("Requires a Mac with Apple silicon")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(palette.secondary)
                    .padding(.leading, 28)
            }
            HStack(spacing: 8) {
                metric("Speed", specs.speed, help: "Audio length divided by processing time on Apple silicon.")
                metric("Size", specs.size, help: specs.sizeNote)
                metric("WER", specs.wordErrorRate, help: "Average word error rate on the Open ASR Leaderboard’s English sets. Lower is better.")
            }
            if case .downloading(let fraction) = modelState {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .tint(palette.foreground)
            }
        }
        .padding(14)
        .foregroundStyle(palette.foreground)
        .background(palette.foreground.opacity(isSelected ? 0.09 : 0.035), in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(palette.foreground.opacity(isSelected ? 0.75 : 0.16)))
        .contentShape(.rect(cornerRadius: 14))
        .onTapGesture { if model.isSupported { select() } }
        .opacity(model.isSupported ? 1 : 0.45)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(model.name) by \(specs.publisher), \(specs.badge), \(specs.size), word error rate \(specs.wordErrorRate)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { if model.isSupported { select() } }
    }

    private func metric(_ label: String, _ value: String, help: String) -> some View {
        HStack {
            Text(label).font(.system(size: 11, design: .rounded)).foregroundStyle(palette.secondary)
            Spacer(minLength: 4)
            Text(value).font(.system(size: 14, weight: .semibold, design: .rounded)).monospacedDigit()
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(palette.foreground.opacity(0.05), in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(palette.foreground.opacity(0.12)))
        .help(help)
    }

    @ViewBuilder
    private var status: some View {
        switch modelState {
        case .downloading(let fraction):
            statusLabel("Downloading \(Int((fraction * 100).rounded()))%")
        case .loading:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Preparing").font(.system(size: 12, weight: .medium, design: .rounded))
            }
        case .failed:
            if showsDownloadButton { downloadButton("Retry") } else { statusLabel("Failed") }
        case .ready:
            statusLabel("Ready", systemImage: "checkmark")
        case nil:
            if service.isModelInstalled(model) {
                statusLabel("Installed", systemImage: "checkmark")
            } else if showsDownloadButton && model.isSupported {
                downloadButton("Download")
            } else {
                statusLabel("Not downloaded")
            }
        }
    }

    private func statusLabel(_ text: String, systemImage: String? = nil) -> some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 10, weight: .bold)) }
            Text(text)
        }
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(palette.foreground.opacity(0.1), in: .capsule)
    }

    private func downloadButton(_ title: String) -> some View {
        Button(title) {
            let model = model
            Task { try? await service.prepareModel(model) }
        }
        .buttonStyle(.plain)
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .foregroundStyle(palette.background)
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(palette.foreground, in: .capsule)
        .contentShape(.capsule)
    }
}
