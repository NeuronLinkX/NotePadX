import Foundation

struct Attachment: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var noteID: UUID
    /// Attachments 디렉터리 내 UUID 기반 파일명 (확장자 포함).
    var storedFileName: String
    var originalFileName: String
    var mimeType: String
    var byteSize: Int64
    var createdAt: Date

    init(
        id: UUID = UUID(),
        noteID: UUID,
        storedFileName: String,
        originalFileName: String,
        mimeType: String,
        byteSize: Int64,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.noteID = noteID
        self.storedFileName = storedFileName
        self.originalFileName = originalFileName
        self.mimeType = mimeType
        self.byteSize = byteSize
        self.createdAt = createdAt
    }
}
