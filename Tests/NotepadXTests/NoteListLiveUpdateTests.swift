import XCTest
@testable import NotepadX

/// 편집기에서 제목을 바꿔 저장하면, ContentView가 연결해 두는 EditorViewModel.onNoteUpdated
/// 콜백을 통해 노트 목록이 다음 전체 재조회 없이 즉시 새 제목을 반영해야 한다.
@MainActor
final class NoteListLiveUpdateTests: XCTestCase {
    private var tempURL: URL!

    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotepadXNoteListLiveUpdateTests-\(UUID().uuidString).sqlite")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempURL)
    }

    private func makeDatabase() async throws -> DatabaseManager {
        let db = try DatabaseManager(databaseURL: tempURL)
        try await SchemaMigrator.migrate(db)
        return db
    }

    func testTitleEditPropagatesToNoteListImmediatelyAfterSave() async throws {
        let db = try await makeDatabase()
        let noteRepo = SQLiteNoteRepository(db: db)
        let index = SearchIndexService(db: db)
        let noteUseCase = NoteUseCase(noteRepository: noteRepo, searchIndex: index)
        let searchUseCase = SearchUseCase(searchIndex: index)
        let tagUseCase = TagUseCase(tagRepository: SQLiteTagRepository(db: db), searchIndex: index)
        let revisionUseCase = NoteRevisionUseCase(
            revisionRepository: SQLiteNoteRevisionRepository(db: db),
            noteRepository: noteRepo
        )

        let created = try await noteUseCase.createNote(folderID: nil)

        let noteList = NoteListViewModel(noteUseCase: noteUseCase, tagUseCase: tagUseCase, searchUseCase: searchUseCase)
        await noteList.load(filter: .all)
        XCTAssertEqual(noteList.notes.first?.title, "")

        // ContentView.init이 하는 것과 동일한 배선: 편집기 저장 콜백이 노트 목록을 갱신한다.
        let editor = EditorViewModel(noteUseCase: noteUseCase, tagUseCase: tagUseCase, revisionUseCase: revisionUseCase)
        editor.onNoteUpdated = { [weak noteList] note in noteList?.applyExternalUpdate(note) }
        await editor.load(noteID: created.id)

        editor.title = "새 제목"
        editor.titleChanged()
        await editor.flush()

        XCTAssertEqual(noteList.notes.first?.title, "새 제목", "저장 직후 목록의 제목이 즉시 갱신되어야 한다")
    }

    func testUpdateForUnknownNoteIsIgnored() async throws {
        let db = try await makeDatabase()
        let noteRepo = SQLiteNoteRepository(db: db)
        let index = SearchIndexService(db: db)
        let noteUseCase = NoteUseCase(noteRepository: noteRepo, searchIndex: index)
        let searchUseCase = SearchUseCase(searchIndex: index)
        let tagUseCase = TagUseCase(tagRepository: SQLiteTagRepository(db: db), searchIndex: index)

        let existing = try await noteUseCase.createNote(folderID: nil)
        let noteList = NoteListViewModel(noteUseCase: noteUseCase, tagUseCase: tagUseCase, searchUseCase: searchUseCase)
        await noteList.load(filter: .all)

        let unrelated = Note(id: UUID(), folderID: nil, title: "다른 노트", documentJSON: Data(), plainText: "", contentHash: "x")
        noteList.applyExternalUpdate(unrelated)

        XCTAssertEqual(noteList.notes.count, 1)
        XCTAssertEqual(noteList.notes.first?.id, existing.id)
    }
}
