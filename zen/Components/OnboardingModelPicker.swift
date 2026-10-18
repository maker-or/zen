import SwiftUI

struct OnboardingModelPicker: View {
    @ObservedObject var state: ZenState
    @ObservedObject var service: TranscriptionService
    let isPreparing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ForEach(TranscriptionModel.allCases) { model in
                    choice(model)
                }
            }
            preparationStatus
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(OnboardingPalette.secondary)
                .frame(minHeight: 20, alignment: .leading)
        }
        .frame(maxWidth: 560, alignment: .leading)
    }

    private func choice(_ model: TranscriptionModel) -> some View {
        let selected = state.transcriptionModel == model
        return Button { state.transcriptionModel = model } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(model.name)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16))
                }
                .foregroundStyle(OnboardingPalette.accent)
                Text(model.isSupported ? (model == .voz ? "Multilingual" : "English") : "Requires Apple silicon")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(OnboardingPalette.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OnboardingPalette.accent.opacity(selected ? 0.09 : 0.025), in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(OnboardingPalette.accent.opacity(selected ? 0.8 : 0.2)))
            .contentShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(!model.isSupported || isPreparing)
        .opacity(model.isSupported ? 1 : 0.45)
        .accessibilityLabel("\(model.name), \(model == .voz ? "multilingual" : "English")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var preparationStatus: some View {
        switch service.modelStates[state.transcriptionModel] {
        case .ready:
            Label("\(state.transcriptionModel.name) is ready", systemImage: "checkmark")
        case .downloading(let fraction):
            HStack(spacing: 12) {
                ProgressView(value: fraction).progressViewStyle(.linear)
                    .tint(OnboardingPalette.accent).frame(maxWidth: 260)
                Text("\(Int(fraction * 100))%")
                    .monospacedDigit()
            }
        case .loading:
            Text("Preparing \(state.transcriptionModel.name) on your Mac…")
        case .failed(let message):
            Text("Couldn’t prepare the model. Check your connection and retry.")
                .fixedSize(horizontal: false, vertical: true)
                .help(message)
        case nil:
            Text("First-time preparation can take a few minutes.")
        }
    }
}
