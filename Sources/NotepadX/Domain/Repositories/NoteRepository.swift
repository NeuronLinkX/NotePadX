import Foundation

enum NoteListFilter: Sendable, Equatable {
    case all
    case folder(UUID)
    case favorites
    case trash
    case recent
    case tag(UUID)
}

enum NoteSortOrder: Sendable, Equatable {
    case updatedDescending
    case createdDescending
    case titleAscending
}

protocol NoteRepository: Sendable {
    func fetchNotes(filter: NoteListFilter, sortOrder: NoteSortOrder) async throws -> [Note]
    func fetchNote(id: UUID) async throws -> Note?
    func createNote(_ note: Note) async throws
    func updateNote(_ note: Note) async throws
    /// 낙관적 동시성 제어(CAS) 저장. `note.id`의 현재 DB상 updated_at이 `expectedUpdatedAt`과
    /// 정확히 같을 때만 갱신하고, 그렇지 않으면(다른 곳에서 먼저 저장됨) 아무것도 바꾸지 않고
    /// false를 돌려준다. 같은 문서를 두 분할 패널에서 동시에 편집할 때 조용히 덮어쓰지 않기 위함이다.
    func updateNoteIfUnchanged(_ note: Note, expectedUpdatedAt: Date) async throws -> Bool
    /// 휴지통으로 이동 (deletedAt 설정). 완전 삭제가 아니다.
    func softDeleteNote(id: UUID) async throws
    func restoreNote(id: UUID) async throws
    /// 휴지통 보관 기간(기본 30일)이 지난 노트를 영구 삭제한다.
    func purgeExpiredTrash(olderThan cutoff: Date) async throws
    /// 휴지통에서 사용자가 명시적으로 "지금 완전히 삭제"를 선택했을 때 호출한다.
    func deleteNotePermanently(id: UUID) async throws
    func setFavorite(id: UUID, isFavorite: Bool) async throws
}
