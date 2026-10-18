import Foundation

nonisolated struct TranscriptWord: Sendable {
    let text: String
    let start: TimeInterval
    let end: TimeInterval
}

nonisolated struct Transcript: Equatable, Sendable {
    let text: String
    let segments: [TranscriptSegment]
}

/// A run of words with the time span it covers, in seconds from the start of the audio.
nonisolated struct TranscriptSegment: Equatable, Sendable {
    let start: TimeInterval
    let end: TimeInterval
    let text: String

    /// Splits timed words into readable segments: at pauses, after a sentence
    /// once the segment has some length, and before it grows too long.
    static func group(_ words: [TranscriptWord]) -> [TranscriptSegment] {
        var segments: [TranscriptSegment] = []
        var current: [TranscriptWord] = []

        func flush() {
            guard let first = current.first, let last = current.last else { return }
            let text = current.map(\.text).joined(separator: " ")
            segments.append(TranscriptSegment(start: first.start, end: last.end, text: text))
            current = []
        }

        for word in words {
            if let first = current.first, let last = current.last {
                let pause = word.start - last.end
                let length = last.end - first.start
                let endsSentence = last.text.last.map { ".!?".contains($0) } ?? false
                if pause > 1.0 || (endsSentence && length > 4) || length > 15 {
                    flush()
                }
            }
            current.append(word)
        }
        flush()
        return segments
    }
}

