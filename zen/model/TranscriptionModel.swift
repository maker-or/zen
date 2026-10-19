import Foundation

nonisolated enum TranscriptionModel: String, CaseIterable, Identifiable, Sendable {
    case voz
    case phonon2 = "phonon-2"

    var id: String { rawValue }
    var name: String { self == .voz ? "Voz" : "Phonon-2" }
    var description: String {
        switch self {
        case .voz: return "Multilingual transcription using the Apple Neural Engine."
        case .phonon2: return "English transcription by Fermion Research using the Apple Neural Engine."
        }
    }
    var isSupported: Bool {
        #if arch(arm64)
        true
        #else
        self == .voz
        #endif
    }

    /// Published figures from each model's card (checked October 2026).
    /// WER is the mean over the Open ASR Leaderboard's English test sets:
    /// six for Voz, seven for Phonon-2. Speed is audio duration divided by
    /// processing time on Apple silicon, so it varies by Mac.
    var specs: Specs {
        switch self {
        case .voz:
            return Specs(badge: "Multilingual", publisher: "Desert Ant Labs",
                         page: URL(string: "https://huggingface.co/desert-ant-labs/voz")!,
                         speed: "~290×", size: "467 MB", sizeNote: "Download size.",
                         wordErrorRate: "7.40%")
        case .phonon2:
            return Specs(badge: "English", publisher: "Fermion Research",
                         page: URL(string: "https://huggingface.co/FermionResearch/Phonon-2-CoreML")!,
                         speed: "~400×", size: "345 MB",
                         sizeNote: "Download size of the Core ML build Zen runs on the Neural Engine. The original Phonon-2 release for MLX is 164 MB.",
                         wordErrorRate: "5.21%")
        }
    }

    struct Specs: Sendable {
        let badge: String
        /// Credited next to the name; links to the model's published card.
        let publisher: String
        let page: URL
        let speed: String
        /// What Zen downloads, which can differ from a model's other releases.
        let size: String
        let sizeNote: String
        let wordErrorRate: String
    }
}
