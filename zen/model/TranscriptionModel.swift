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
}
