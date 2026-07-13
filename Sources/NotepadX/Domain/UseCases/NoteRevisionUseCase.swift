import Foundation

struct NoteRevisionUseCase: Sendable {
    static let defaultKeepCount = 20
    /// "일정 시간 이상 편집 후" 조건 (스펙 11절)에 쓰는 최소 간격.
    static let periodicSnapshotInterval: TimeInterval = 300

    private let revisionRepository: any NoteRevisionRepository
    private let noteRepository: any NoteRepository

    init(revisionRepository: any NoteRevisionRepository, noteRepository: any NoteRepository) {
        self.revisionRepository = revisionRepository
        self.noteRepository = noteRepository
    }

    func revisions(forNote noteID: UUID) async throws -> [NoteRevision] {
        try await revisionRepository.revisions(forNote: noteID)
    }

    @discardableResult
    func snapshot(note: Note, reason: NoteRevisionReason) async throws -> NoteRevision {
        let revision = NoteRevision(
            noteID: note.id,
            documentJSON: note.documentJSON,
            plainText: note.plainText,
            reason: reason
        )
        try await revisionRepository.createRevision(revision)
        try await revisionRepository.pruneOldRevisions(noteID: note.id, keep: Self.defaultKeepCount)
        return revision
    }

    /// 이전 버전을 복원한다. 복원 전 현재 내용을 자동으로 리비전에 보관한다 (스펙 11절).
    func restore(revisionID: UUID) async throws -> Note {
        guard let revision = try await revisionRepository.revision(id: revisionID) else {
            throw AppError.documentCorrupted
        }
        guard let currentNote = try await noteRepository.fetchNote(id: revision.noteID) else {
            throw AppError.documentCorrupted
        }

        try await snapshot(note: currentNote, reason: .beforeRestore)

        var restored = currentNote
        restored.documentJSON = revision.documentJSON
        restored.plainText = revision.plainText
        restored.contentHash = NoteUseCase.contentHash(for: revision.plainText)
        restored.updatedAt = Date()
        try await noteRepository.updateNote(restored)
        return restored
    }
}
