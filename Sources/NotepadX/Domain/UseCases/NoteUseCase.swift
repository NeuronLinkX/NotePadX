import Foundation
import CryptoKit

/// Note 생성/수정에 관한 비즈니스 규칙을 View/ViewModel과 Repository 사이에서 캡슐화한다.
/// SwiftUI 뷰는 이 타입을 통해서만 노트를 변경하고, SQLite나 파일시스템을 직접 건드리지 않는다.
struct NoteUseCase: Sendable {
    private let noteRepository: any NoteRepository
    private let searchIndex: SearchIndexService

    init(noteRepository: any NoteRepository, searchIndex: SearchIndexService) {
        self.noteRepository = noteRepository
        self.searchIndex = searchIndex
    }

    static func contentHash(for plainText: String) -> String {
        let digest = SHA256.hash(data: Data(plainText.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func fetchNotes(filter: NoteListFilter, sortOrder: NoteSortOrder = .updatedDescending) async throws -> [Note] {
        try await noteRepository.fetchNotes(filter: filter, sortOrder: sortOrder)
    }

    func fetchNote(id: UUID) async throws -> Note? {
        try await noteRepository.fetchNote(id: id)
    }

    @discardableResult
    func createNote(folderID: UUID?) async throws -> Note {
        let document = EditorDocument.fromPlainText("")
        let note = Note(
            folderID: folderID,
            title: "",
            documentJSON: try document.encoded(),
            plainText: "",
            contentHash: Self.contentHash(for: "")
        )
        try await noteRepository.createNote(note)
        try await searchIndex.reindexNote(id: note.id)
        return note
    }

    /// WKWebView 리치 에디터(Tiptap)가 보내온 구조화 문서로 노트를 갱신한다.
    /// plainText는 JS가 함께 보내주는 파생값을 그대로 신뢰한다 — EditorDocument.derivedPlainText와
    /// 동일한 알고리즘을 두 곳에서 유지보수하지 않기 위해서다.
    func applyEdit(to note: Note, title: String, document: EditorDocument, plainText: String) throws -> Note {
        var updated = note
        updated.title = title
        updated.plainText = plainText
        updated.documentJSON = try document.encoded()
        updated.contentHash = Self.contentHash(for: plainText)
        updated.updatedAt = Date()
        return updated
    }

    func save(_ note: Note) async throws {
        try await noteRepository.updateNote(note)
        try await searchIndex.reindexNote(id: note.id)
    }

    /// 분할 편집에서 같은 노트를 두 패널이 동시에 열고 있을 수 있으므로, 저장 직전 이 패널이
    /// 마지막으로 알고 있던 `expectedUpdatedAt`과 DB의 현재 updated_at이 다르면 (다른 패널이
    /// 먼저 저장했다는 뜻) 덮어쓰지 않고 false를 돌려준다. 호출자는 이 값으로 충돌을 알리고
    /// 자동으로 재시도하거나 병합하지 않는다 — 데이터 손실과 무한 루프를 둘 다 피하기 위해서다.
    @discardableResult
    func saveIfUnchanged(_ note: Note, expectedUpdatedAt: Date) async throws -> Bool {
        let didSave = try await noteRepository.updateNoteIfUnchanged(note, expectedUpdatedAt: expectedUpdatedAt)
        if didSave {
            try await searchIndex.reindexNote(id: note.id)
        }
        return didSave
    }

    func moveToTrash(id: UUID) async throws {
        try await noteRepository.softDeleteNote(id: id)
        try await searchIndex.removeFromIndex(id: id)
    }

    func restore(id: UUID) async throws {
        try await noteRepository.restoreNote(id: id)
        try await searchIndex.reindexNote(id: id)
    }

    /// 휴지통에서 사용자가 "지금 완전히 삭제"를 선택했을 때 호출한다. 30일 자동 만료를 기다리지 않는다.
    func deletePermanently(id: UUID) async throws {
        try await noteRepository.deleteNotePermanently(id: id)
        try await searchIndex.removeFromIndex(id: id)
    }

    func setFavorite(id: UUID, isFavorite: Bool) async throws {
        try await noteRepository.setFavorite(id: id, isFavorite: isFavorite)
    }

    /// 휴지통 30일 보관 정책 (스펙 11절).
    func purgeExpiredTrash(retentionDays: Int = 30) async throws {
        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? Date.distantPast
        try await noteRepository.purgeExpiredTrash(olderThan: cutoff)
    }
}
