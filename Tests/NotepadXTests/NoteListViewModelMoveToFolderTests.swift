import XCTest
@testable import NotepadX

/// 메모 목록에서 사이드바 폴더로 드래그 앤 드롭했을 때 호출되는 `moveNotes`를 검증한다:
/// 폴더별 화면에서는 다른 폴더로 옮기면 그 자리에서 사라지고, 폴더를 가리지 않는 화면
/// ("모든 메모" 등)에서는 목록에 남되 folderID만 갱신된다.
@MainActor
final class NoteListViewModelMoveToFolderTests: XCTestCase {
    private var tempURL: URL!

    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotepadXMoveToFolderTests-\(UUID().uuidString).sqlite")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempURL)
    }

    private func makeStack() async throws -> (list: NoteListViewModel, notes: NoteUseCase, folders: FolderUseCase) {
        let db = try DatabaseManager(databaseURL: tempURL)
        try await SchemaMigrator.migrate(db)
        let index = SearchIndexService(db: db)
        let noteUseCase = NoteUseCase(noteRepository: SQLiteNoteRepository(db: db), searchIndex: index)
        let tagUseCase = TagUseCase(tagRepository: SQLiteTagRepository(db: db), searchIndex: index)
        let searchUseCase = SearchUseCase(searchIndex: index)
        let folderUseCase = FolderUseCase(
            folderRepository: SQLiteFolderRepository(db: db),
            noteRepository: SQLiteNoteRepository(db: db),
            searchIndex: index
        )
        let list = NoteListViewModel(noteUseCase: noteUseCase, tagUseCase: tagUseCase, searchUseCase: searchUseCase)
        return (list, noteUseCase, folderUseCase)
    }

    func testMovingNoteOutOfCurrentFolderRemovesItFromTheList() async throws {
        let (list, notes, folders) = try await makeStack()
        let source = try await folders.createFolder(name: "출발", parentID: nil)
        let destination = try await folders.createFolder(name: "도착", parentID: nil)
        let note = try await notes.createNote(folderID: source.id)
        await list.load(filter: .folder(source.id))
        XCTAssertEqual(list.notes.map(\.id), [note.id])

        await list.moveNotes([note.id], toFolderID: destination.id)

        XCTAssertTrue(list.notes.isEmpty)
        let persisted = try await notes.fetchNote(id: note.id)
        XCTAssertEqual(persisted?.folderID, destination.id)
    }

    func testMovingNoteWhileViewingAllNotesKeepsItInPlaceWithUpdatedFolder() async throws {
        let (list, notes, folders) = try await makeStack()
        let destination = try await folders.createFolder(name: "도착", parentID: nil)
        let note = try await notes.createNote(folderID: nil)
        await list.load(filter: .all)

        await list.moveNotes([note.id], toFolderID: destination.id)

        XCTAssertEqual(list.notes.map(\.id), [note.id])
        XCTAssertEqual(list.notes.first?.folderID, destination.id)
        let persisted = try await notes.fetchNote(id: note.id)
        XCTAssertEqual(persisted?.folderID, destination.id)
    }

    func testMovingSelectedNoteOutOfCurrentFolderClearsSelection() async throws {
        let (list, notes, folders) = try await makeStack()
        let source = try await folders.createFolder(name: "출발", parentID: nil)
        let destination = try await folders.createFolder(name: "도착", parentID: nil)
        let note = try await notes.createNote(folderID: source.id)
        await list.load(filter: .folder(source.id))
        list.selectedNoteID = note.id

        await list.moveNotes([note.id], toFolderID: destination.id)

        XCTAssertNil(list.selectedNoteID)
    }

    func testMovingEmptySetDoesNothing() async throws {
        let (list, notes, folders) = try await makeStack()
        let destination = try await folders.createFolder(name: "도착", parentID: nil)
        _ = try await notes.createNote(folderID: nil)
        await list.load(filter: .all)
        let before = list.notes

        await list.moveNotes([], toFolderID: destination.id)

        XCTAssertEqual(list.notes.map(\.id), before.map(\.id))
    }
}
