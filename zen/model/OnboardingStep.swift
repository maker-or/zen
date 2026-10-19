nonisolated enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome, capture, privacy, models, paste, microphone

    var id: Int { rawValue }
    var next: Self? { Self(rawValue: rawValue + 1) }
    var previous: Self? { Self(rawValue: rawValue - 1) }

    var navigationTitle: String {
        switch self {
        case .welcome: return "Introduction"
        case .capture: return "Recording shortcut"
        case .privacy: return "On-device transcription"
        case .models: return "Model selection and download"
        case .paste: return "Automatic paste"
        case .microphone: return "Microphone setup"
        }
    }
}
