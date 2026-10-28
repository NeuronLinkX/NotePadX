import XCTest
@testable import NotepadX

/// 즐겨찾기·고정은 목록에서 전용 메서드로만 바꾸는 값이다. 편집기는 열 때 읽어 둔 복사본으로 자동 저장하므로,
/// 저장이 그 (오래된) 값을 되써서 목록에서 바꾼 상태를 되돌려 버리면 안 된다.
final class NoteFlagPersistenceTests: XCTestCase {
    private var tempURL: URL!

    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("NotepadXFlags-\(UUID().uuidString).sqlite")
    }

    override func tearDownWithError() throws {
        for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: tempURL.path + suffix) }
    }

    private func makeUseCase() async throws -> NoteUseCase {
        let db = try DatabaseManager(databaseURL: tempURL)
        try await SchemaMigrator.migrate(db)
        return NoteUseCase(noteRepository: SQLiteNoteRepository(db: db), searchIndex: SearchIndexService(db: db))
    }

    private func editedCopy(of note: Note, in useCase: NoteUseCase) -> Note {
        useCase.applyEdit(to: note, title: "수정됨", documentJSON: Data("{}".utf8), plainText: "새 내용")
    }

    func testAutosaveFromAStaleEditorCopyDoesNotRevertAFavoriteSetFromTheList() async throws {
        let useCase = try await makeUseCase()
        let stale = try await useCase.createNote(folderID: nil)   // 편집기가 열 때 읽어 둔 복사본(즐겨찾기 아님)

        try await useCase.setFavorite(id: stale.id, isFavorite: true)   // 그 사이 목록에서 별표
        try await useCase.save(editedCopy(of: stale, in: useCase))      // 편집기 자동 저장

        let reloaded = try await useCase.fetchNote(id: stale.id)
        XCTAssertEqual(reloaded?.isFavorite, true, "자동 저장이 목록에서 켠 즐겨찾기를 꺼 버리면 안 된다")
        XCTAssertEqual(reloaded?.title, "수정됨", "본문 저장은 정상적으로 되어야 한다")
    }

    func testCASAutosaveAlsoLeavesFlagsAlone() async throws {
        let useCase = try await makeUseCase()
        let stale = try await useCase.createNote(folderID: nil)
        try await useCase.setPinned(id: stale.id, isPinned: true)
        try await useCase.setFavorite(id: stale.id, isFavorite: true)

        _ = try await useCase.saveIfUnchanged(editedCopy(of: stale, in: useCase), expectedUpdatedAt: stale.updatedAt)

        let reloaded = try await useCase.fetchNote(id: stale.id)
        XCTAssertEqual(reloaded?.isPinned, true)
        XCTAssertEqual(reloaded?.isFavorite, true)
    }

    func testPinnedNotesSortFirstAndUnpinningRestoresOrder() async throws {
        let useCase = try await makeUseCase()
        let older = try await useCase.createNote(folderID: nil)
        var newer = try await useCase.createNote(folderID: nil)
        newer.updatedAt = older.updatedAt.addingTimeInterval(100)
        try await useCase.save(newer)

        try await useCase.setPinned(id: older.id, isPinned: true)
        var order = try await useCase.fetchNotes(filter: .all).map(\.id)
        XCTAssertEqual(order.first, older.id, "고정한 메모는 더 오래됐어도 맨 위")

        try await useCase.setPinned(id: older.id, isPinned: false)
        order = try await useCase.fetchNotes(filter: .all).map(\.id)
        XCTAssertEqual(order.first, newer.id)
    }

    func testPinDoesNotChangeTheModifiedTimeOrContent() async throws {
        let useCase = try await makeUseCase()
        var note = try await useCase.createNote(folderID: nil)
        note = editedCopy(of: note, in: useCase)
        try await useCase.save(note)

        try await useCase.setPinned(id: note.id, isPinned: true)

        let reloaded = try await useCase.fetchNote(id: note.id)
        XCTAssertEqual(reloaded?.updatedAt.timeIntervalSince1970 ?? 0, note.updatedAt.timeIntervalSince1970, accuracy: 0.001, "고정은 '수정됨'이 아니다")
        XCTAssertEqual(reloaded?.plainText, "새 내용")
    }
}

@MainActor
final class NoteListPinTests: XCTestCase {
    private var tempURL: URL!

    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("NotepadXListPin-\(UUID().uuidString).sqlite")
    }

    override func tearDownWithError() throws {
        for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: tempURL.path + suffix) }
    }

    private func makeList() async throws -> (NoteListViewModel, NoteUseCase) {
        let db = try DatabaseManager(databaseURL: tempURL)
        try await SchemaMigrator.migrate(db)
        let index = SearchIndexService(db: db)
        let useCase = NoteUseCase(noteRepository: SQLiteNoteRepository(db: db), searchIndex: index)
        let list = NoteListViewModel(
            noteUseCase: useCase,
            tagUseCase: TagUseCase(tagRepository: SQLiteTagRepository(db: db), searchIndex: index),
            searchUseCase: SearchUseCase(searchIndex: index)
        )
        return (list, useCase)
    }

    func testTogglingPinMovesTheRowToTheTopImmediatelyAndBack() async throws {
        let (list, useCase) = try await makeList()
        let first = try await useCase.createNote(folderID: nil)
        var second = try await useCase.createNote(folderID: nil)
        second.updatedAt = first.updatedAt.addingTimeInterval(50)
        try await useCase.save(second)
        await list.load(filter: .all)
        XCTAssertEqual(list.notes.first?.id, second.id)

        await list.togglePinned(list.notes.first(where: { $0.id == first.id })!)
        XCTAssertEqual(list.notes.first?.id, first.id, "고정하면 더 오래된 메모라도 맨 위로")
        XCTAssertEqual(list.notes.first?.isPinned, true)

        await list.togglePinned(list.notes.first!)
        XCTAssertEqual(list.notes.first?.id, second.id)
        XCTAssertEqual(list.notes.first(where: { $0.id == first.id })?.isPinned, false)
    }

    func testEditorSaveCallbackKeepsThePinAndStarShownInTheList() async throws {
        let (list, useCase) = try await makeList()
        let stale = try await useCase.createNote(folderID: nil)   // 편집기가 들고 있는 오래된 복사본
        await list.load(filter: .all)
        await list.togglePinned(list.notes[0])
        await list.toggleFavorite(list.notes[0])

        list.applyExternalUpdate(useCase.applyEdit(to: stale, title: "새 제목", documentJSON: Data("{}".utf8), plainText: "x"))

        XCTAssertEqual(list.notes[0].title, "새 제목")
        XCTAssertTrue(list.notes[0].isPinned, "목록의 핀이 편집기의 오래된 값에 덮여 사라지면 안 된다")
        XCTAssertTrue(list.notes[0].isFavorite)
    }
}
