import Foundation

protocol NoteRevisionRepository: Sendable {
    func createRevision(_ revision: NoteRevision) async throws
    func revisions(forNote noteID: UUID) async throws -> [NoteRevision]
    func revision(id: UUID) async throws -> NoteRevision?
    /// 최근 `keep`개만 남기고 오래된 리비전을 지운다 (스펙 11절 기본 20개).
    func pruneOldRevisions(noteID: UUID, keep: Int) async throws
}
