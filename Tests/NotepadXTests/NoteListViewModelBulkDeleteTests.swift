import XCTest
@testable import NotepadX

/// 체크상자로 메모를 여러 개 골라 한꺼번에 삭제하는 기능과, 영구 삭제 시 더 이상 어떤
/// 노트에도 쓰이지 않는 태그를 자동으로 정리하는 동작을 검증한다.
@MainActor
final class NoteListViewModelBulkDeleteTests: XCTestCase {
    private var tempURL: URL!

    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotepadXBulkDeleteTests-\(UUID().uuidString).sqlite")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempURL)
    }

    private func makeStack() async throws -> (list: NoteListViewModel, notes: NoteUseCase, tags: TagUseCase) {
        let db = try DatabaseManager(databaseURL: tempURL)
        try await SchemaMigrator.migrate(db)
        let index = SearchIndexService(db: db)
        let noteUseCase = NoteUseCase(noteRepository: SQLiteNoteRepository(db: db), searchIndex: index)
        let tagUseCase = TagUseCase(tagRepository: SQLiteTagRepository(db: db), searchIndex: index)
        let searchUseCase = SearchUseCase(searchIndex: index)
        let list = NoteListViewModel(noteUseCase: noteUseCase, tagUseCase: tagUseCase, searchUseCase: searchUseCase)
        return (list, noteUseCase, tagUseCase)
    }

    // MARK: - 선택 모드

    func testToggleSelectionModeClearsCheckedNotesOnExit() async throws {
        let (list, notes, _) = try await makeStack()
        let note = try await notes.createNote(folderID: nil)
        await list.load(filter: .all)

        list.toggleSelectionMode()
        list.toggleChecked(note.id)
        XCTAssertTrue(list.isSelecting)
        XCTAssertEqual(list.checkedNoteIDs, [note.id])

        list.toggleSelectionMode()
        XCTAssertFalse(list.isSelecting)
        XCTAssertTrue(list.checkedNoteIDs.isEmpty)
    }

    func testSelectAllVisibleAndDeselectAll() async throws {
        let (list, notes, _) = try await makeStack()
        _ = try await notes.createNote(folderID: nil)
        _ = try await notes.createNote(folderID: nil)
        await list.load(filter: .all)

        list.selectAllVisible()
        XCTAssertEqual(list.checkedNoteIDs.count, 2)

        list.deselectAll()
        XCTAssertTrue(list.checkedNoteIDs.isEmpty)
    }

    // MARK: - 여러 개 휴지통으로 이동 (소프트 삭제) — 태그는 그대로 둔다

    func testBulkMoveToTrashRemovesFromListButKeepsTags() async throws {
        let (list, notes, tags) = try await makeStack()
        let noteA = try await notes.createNote(folderID: nil)
        let noteB = try await notes.createNote(folderID: nil)
        let tag = try await tags.createTag(name: "회의")
        try await tags.setTags(noteID: noteA.id, tagIDs: [tag.id])
        await list.load(filter: .all)

        list.toggleSelectionMode()
        list.toggleChecked(noteA.id)
        list.toggleChecked(noteB.id)
        await list.deleteCheckedNotes(permanently: false)

        XCTAssertTrue(list.notes.isEmpty)
        XCTAssertFalse(list.isSelecting)
        XCTAssertTrue(list.checkedNoteIDs.isEmpty)

        let allTags = try await tags.fetchAllTags()
        XCTAssertEqual(allTags.map(\.name), ["회의"], "휴지통 이동(소프트 삭제)에서는 태그를 지우면 안 된다 — 복원하면 태그도 돌아와야 한다")
    }

    // MARK: - 영구 삭제 — 더 이상 안 쓰이는 태그는 자동으로 지운다

    func testBulkPermanentDeletePrunesOrphanedTags() async throws {
        let (list, notes, tags) = try await makeStack()
        let noteA = try await notes.createNote(folderID: nil)
        let noteB = try await notes.createNote(folderID: nil)
        let onlyOnA = try await tags.createTag(name: "일회성")
        let sharedTag = try await tags.createTag(name: "공용")
        try await tags.setTags(noteID: noteA.id, tagIDs: [onlyOnA.id, sharedTag.id])
        try await tags.setTags(noteID: noteB.id, tagIDs: [sharedTag.id])
        await list.load(filter: .all)

        var tagsChangedFired = false
        list.onTagsChanged = { tagsChangedFired = true }

        list.toggleSelectionMode()
        list.toggleChecked(noteA.id)
        await list.deleteCheckedNotes(permanently: true)

        let remaining = try await tags.fetchAllTags()
        XCTAssertEqual(remaining.map(\.name).sorted(), ["공용"], "noteA에만 있던 '일회성' 태그는 자동으로 지워지고, noteB가 여전히 쓰는 '공용' 태그는 남아야 한다")
        XCTAssertTrue(tagsChangedFired, "태그가 정리됐으면 사이드바가 갱신되도록 콜백이 호출되어야 한다")
    }

    func testBulkPermanentDeleteDoesNotFireOnTagsChangedWhenNoTagWasPruned() async throws {
        let (list, notes, tags) = try await makeStack()
        let noteA = try await notes.createNote(folderID: nil)
        let noteB = try await notes.createNote(folderID: nil)
        let sharedTag = try await tags.createTag(name: "공용")
        try await tags.setTags(noteID: noteA.id, tagIDs: [sharedTag.id])
        try await tags.setTags(noteID: noteB.id, tagIDs: [sharedTag.id])
        await list.load(filter: .all)

        var tagsChangedFired = false
        list.onTagsChanged = { tagsChangedFired = true }

        list.toggleSelectionMode()
        list.toggleChecked(noteA.id)
        await list.deleteCheckedNotes(permanently: true)

        let remaining = try await tags.fetchAllTags()
        XCTAssertEqual(remaining.map(\.name), ["공용"], "noteB가 여전히 쓰고 있으니 지워지면 안 된다")
        XCTAssertFalse(tagsChangedFired)
    }

    func testSingleNotePermanentDeleteAlsoPrunesOrphanedTags() async throws {
        let (list, notes, tags) = try await makeStack()
        let note = try await notes.createNote(folderID: nil)
        let tag = try await tags.createTag(name: "혼자")
        try await tags.setTags(noteID: note.id, tagIDs: [tag.id])
        await list.load(filter: .all)

        await list.deletePermanently(list.notes[0])

        let remaining = try await tags.fetchAllTags()
        XCTAssertTrue(remaining.isEmpty, "기존 단일 노트 영구 삭제 경로도 고아 태그를 정리해야 한다")
    }
}
