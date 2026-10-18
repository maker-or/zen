import SwiftUI

struct AppSettingsView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var state = ZenState.shared
    @ObservedObject private var service = TranscriptionService.shared

    private var model: TranscriptionModel { state.transcriptionModel }
    private var modelState: TranscriptionService.ModelState? { service.modelStates[model] }
    private var isPreparing: Bool {
        switch modelState {
        case .loading, .downloading: return true
        default: return false
        }
    }

    var body: some View {
        Form {
            Section {
                Picker("Transcription model", selection: $state.transcriptionModel) {
                    ForEach(TranscriptionModel.allCases) { model in
                        Text(model.name).tag(model)
                            .disabled(!model.isSupported)
                    }
                }
                .pickerStyle(.radioGroup)

                Text(model.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Speech recognition")
            } footer: {
                Text("Used for voice memos and audio or video files. Changes apply to the next transcription.")
            }

            Section {
                preparationStatus

                if !service.isModelLoaded(model) {
                    Button(isPreparing ? "Preparing…" : "Download & Prepare") {
                        let selectedModel = model
                        Task { try? await service.prepareModel(selectedModel) }
                    }
                    .disabled(isPreparing || !model.isSupported)
                }
            } header: {
                Text("Model availability")
            } footer: {
                Text("The model is downloaded once and runs on this Mac. Audio stays on your device.")
            }

            if model == .phonon2 {
                Section {
                    Link("Phonon-2 by Fermion Research", destination: URL(string: "https://huggingface.co/FermionResearch/Phonon-2-CoreML")!)
                    Text("Based on NVIDIA Parakeet TDT. Model weights licensed under CC BY 4.0.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Replay introduction") { openWindow(id: "onboarding") }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 430)
    }

    @ViewBuilder
    private var preparationStatus: some View {
        if !model.isSupported {
            Label("Phonon-2 requires a Mac with Apple silicon.", systemImage: "info.circle")
        } else {
            switch modelState {
            case .ready:
                Label("Ready to transcribe", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .loading:
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Preparing \(model.name)…")
                }
                Text("First-time preparation can take a few minutes.")
                    .font(.caption).foregroundStyle(.secondary)
            case .downloading(let fraction):
                ProgressView(value: fraction) {
                    Text("Downloading \(model.name)…")
                } currentValueLabel: {
                    Text(fraction, format: .percent.precision(.fractionLength(0)))
                }
            case .failed(let message):
                Label("Couldn’t prepare \(model.name)", systemImage: "exclamationmark.triangle")
                Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            case nil:
                Text("\(model.name) will prepare automatically on first use.")
            }
        }
    }
}
