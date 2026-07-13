import Foundation

/// 버전 기록이 생성된 계기. beforeLLMReplace/beforeExternalSync/beforeConflictResolution은
/// 그 기능(LLM, OneDrive 동기화)이 아직 없는 Phase 3 시점에는 생성되지 않고,
/// 해당 Phase에서 실제 호출부가 추가된다.
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
