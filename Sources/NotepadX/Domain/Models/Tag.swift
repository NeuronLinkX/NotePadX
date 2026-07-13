import Foundation

struct Tag: Identifiable, Codable, Sendable, Equatable, Hashable {
    let id: UUID
    var name: String
    var colorHex: String?

    init(id: UUID = UUID(), name: String, colorHex: String? = nil) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
    }
}

/// Note와 Tag의 다대다 연결.
struct NoteTagLink: Codable, Sendable, Equatable {
    var noteID: UUID
    var tagID: UUID
}
