import SwiftUI

struct OnboardingModelPicker: View {
    @ObservedObject var state: ZenState
    @ObservedObject var service: TranscriptionService
    let isPreparing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(TranscriptionModel.allCases) { model in
                ModelCard(model: model, isSelected: state.transcriptionModel == model,
                          palette: .onboarding, showsDownloadButton: false) {
                    state.transcriptionModel = model
                    service.preloadIfInstalled(model)
                }
            }
            preparationStatus
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(OnboardingPalette.secondary)
        }
        .frame(maxWidth: 560, alignment: .leading)
    }

    @ViewBuilder
    private var preparationStatus: some View {
        switch service.modelStates[state.transcriptionModel] {
        case .failed(let message):
            Text("Couldn’t prepare the model. Check your connection and retry.")
                .fixedSize(horizontal: false, vertical: true)
                .help(message)
        default:
            EmptyView()
        }
    }
}
