import Foundation

struct FolderUseCase: Sendable {
    private let folderRepository: any FolderRepository
    private let noteRepository: any NoteRepository
    private let searchIndex: SearchIndexService

    init(folderRepository: any FolderRepository, noteRepository: any NoteRepository, searchIndex: SearchIndexService) {
        self.folderRepository = folderRepository
        self.noteRepository = noteRepository
        self.searchIndex = searchIndex
    }

    func fetchAllFolders() async throws -> [Folder] {
        try await folderRepository.fetchAllFolders()
    }

    @discardableResult
    func createFolder(name: String, parentID: UUID?) async throws -> Folder {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let folder = Folder(parentID: parentID, name: trimmed.isEmpty ? "새 폴더" : trimmed)
        try await folderRepository.createFolder(folder)
        return folder
    }

    /// 폴더 이름은 검색 색인(note_fts.folder_name)에도 들어가 있으므로,
    /// 이름을 바꾸면 그 폴더에 속한 노트들의 색인을 다시 만든다.
    func rename(id: UUID, to newName: String) async throws {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try await folderRepository.renameFolder(id: id, newName: trimmed)
        try await searchIndex.reindexAllNotes(folderID: id)
    }

    func move(id: UUID, toParent parentID: UUID?) async throws {
        guard id != parentID else { return }
        try await folderRepository.moveFolder(id: id, newParentID: parentID)
    }

    /// 폴더를 지우면 그 안의 노트는 삭제되지 않고 folder_id가 NULL로 바뀐다
    /// (SchemaMigrator의 ON DELETE SET NULL). 삭제 전 소속 노트 목록을 미리 구해뒀다가
    /// 삭제 후 색인의 folder_name을 비운다.
    func delete(id: UUID) async throws {
        let affectedNoteIDs = try await noteRepository.fetchNotes(filter: .folder(id), sortOrder: .updatedDescending).map(\.id)
        try await folderRepository.deleteFolder(id: id)
        for noteID in affectedNoteIDs {
            try await searchIndex.reindexNote(id: noteID)
        }
    }

    func noteCount(folderID: UUID) async throws -> Int {
        try await folderRepository.noteCount(folderID: folderID)
    }
}
