import Foundation

/// A saved transcript in the Memos grid. The ID, not the text, identifies a
/// memo, so two memos with identical words stay distinct.
nonisolated struct Memo: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let text: String

    init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}
