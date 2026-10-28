import Foundation

/// 버전 기록이 생성된 계기. beforeLLMReplace는 AI 기능을 없앤 뒤로 새로 만들어지지 않지만,
/// 예전에 저장된 버전 기록을 읽을 수 있도록 값은 남겨 둔다.
enum NoteRevisionReason: String, Codable, Sendable, CaseIterable {
    case periodicEdit
    case manualSnapshot
    case beforeLargeChange
    case beforeRestore
    case beforeLLMReplace
    case beforeExternalSync
    case beforeConflictResolution
}

struct NoteRevision: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var noteID: UUID
    var documentJSON: Data
    var plainText: String
    var reason: NoteRevisionReason
    var createdAt: Date

    init(
        id: UUID = UUID(),
        noteID: UUID,
        documentJSON: Data,
        plainText: String,
        reason: NoteRevisionReason,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.noteID = noteID
        self.documentJSON = documentJSON
        self.plainText = plainText
        self.reason = reason
        self.createdAt = createdAt
    }
}
