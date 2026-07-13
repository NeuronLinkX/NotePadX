import XCTest
@testable import NotepadX

final class DatabaseTests: XCTestCase {
    private var tempURL: URL!

    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotepadXTests-\(UUID().uuidString).sqlite")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempURL)
    }

    private func makeDatabase() async throws -> DatabaseManager {
        let db = try DatabaseManager(databaseURL: tempURL)
        try await SchemaMigrator.migrate(db)
        return db
    }

    private func makeUseCases(_ db: DatabaseManager) -> (notes: NoteUseCase, folders: FolderUseCase) {
        let index = SearchIndexService(db: db)
        let noteRepo = SQLiteNoteRepository(db: db)
        let folderRepo = SQLiteFolderRepository(db: db)
        return (
            NoteUseCase(noteRepository: noteRepo, searchIndex: index),
            FolderUseCase(folderRepository: folderRepo, noteRepository: noteRepo, searchIndex: index)
        )
    }

    func testMigrationCreatesExpectedTables() async throws {
        let db = try await makeDatabase()
        let tableNames = try await db.query(
            "SELECT name FROM sqlite_master WHERE type IN ('table', 'view') ORDER BY name;"
        ) { $0.string(0) ?? "" }
        XCTAssertTrue(tableNames.contains("note"))
        XCTAssertTrue(tableNames.contains("folder"))
        XCTAssertTrue(tableNames.contains("schema_version"))
        XCTAssertTrue(tableNames.contains("tag"))
        XCTAssertTrue(tableNames.contains("note_tag"))
        XCTAssertTrue(tableNames.contains("note_revision"))
        XCTAssertTrue(tableNames.contains("note_fts"))
    }

    func testMigrationIsIdempotent() async throws {
        let db = try await makeDatabase()
        // 같은 DB에 다시 migrate를 호출해도 오류 없이 통과해야 한다 (버전이 이미 적용됨).
        try await SchemaMigrator.migrate(db)
        let version = try await db.query("SELECT MAX(version) FROM schema_version;") { $0.int(0) ?? 0 }.first
        XCTAssertEqual(version, SchemaMigrator.migrations.map(\.version).max())
    }

    func testNoteCRUDLifecycle() async throws {
        let db = try await makeDatabase()
        let repository = SQLiteNoteRepository(db: db)
        let useCase = makeUseCases(db).notes

        let created = try await useCase.createNote(folderID: nil)
        var fetched = try await repository.fetchNote(id: created.id)
        XCTAssertNotNil(fetched)

        let edited = try useCase.applyEdit(
            to: created,
            title: "테스트 제목",
            document: EditorDocument.fromPlainText("본문 내용"),
            plainText: "본문 내용"
        )
        try await useCase.save(edited)

        fetched = try await repository.fetchNote(id: created.id)
        XCTAssertEqual(fetched?.title, "테스트 제목")
        XCTAssertEqual(fetched?.plainText, "본문 내용")
        XCTAssertEqual(fetched?.contentHash, NoteUseCase.contentHash(for: "본문 내용"))

        try await useCase.moveToTrash(id: created.id)
        let allNotes = try await repository.fetchNotes(filter: .all, sortOrder: .updatedDescending)
        XCTAssertFalse(allNotes.contains { $0.id == created.id })

        let trashed = try await repository.fetchNotes(filter: .trash, sortOrder: .updatedDescending)
        XCTAssertTrue(trashed.contains { $0.id == created.id })

        try await useCase.restore(id: created.id)
        let restored = try await repository.fetchNotes(filter: .all, sortOrder: .updatedDescending)
        XCTAssertTrue(restored.contains { $0.id == created.id })
    }

    func testFavoriteToggle() async throws {
        let db = try await makeDatabase()
        let repository = SQLiteNoteRepository(db: db)
        let useCase = makeUseCases(db).notes

        let note = try await useCase.createNote(folderID: nil)
        try await useCase.setFavorite(id: note.id, isFavorite: true)

        let favorites = try await repository.fetchNotes(filter: .favorites, sortOrder: .updatedDescending)
        XCTAssertTrue(favorites.contains { $0.id == note.id })
    }

    func testExpiredTrashIsPurged() async throws {
        let db = try await makeDatabase()
        let repository = SQLiteNoteRepository(db: db)
        let useCase = makeUseCases(db).notes

        let note = try await useCase.createNote(folderID: nil)
        try await useCase.moveToTrash(id: note.id)

        // 미래 시점을 기준(cutoff)으로 넘겨 "30일보다 오래된 항목"인 것처럼 강제로 만료시킨다.
        try await repository.purgeExpiredTrash(olderThan: Date().addingTimeInterval(60))

        let fetched = try await repository.fetchNote(id: note.id)
        XCTAssertNil(fetched)
    }

    func testPermanentDeleteFromTrash() async throws {
        let db = try await makeDatabase()
        let repository = SQLiteNoteRepository(db: db)
        let useCase = makeUseCases(db).notes

        let note = try await useCase.createNote(folderID: nil)
        try await useCase.moveToTrash(id: note.id)
        try await useCase.deletePermanently(id: note.id)

        let fetched = try await repository.fetchNote(id: note.id)
        XCTAssertNil(fetched)
    }

    func testFolderHierarchyCRUD() async throws {
        let db = try await makeDatabase()
        let useCase = makeUseCases(db).folders

        let parent = try await useCase.createFolder(name: "업무", parentID: nil)
        let child = try await useCase.createFolder(name: "프로젝트 A", parentID: parent.id)

        let all = try await useCase.fetchAllFolders()
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all.first { $0.id == child.id }?.parentID, parent.id)

        try await useCase.rename(id: parent.id, to: "업무 (개편)")
        let renamed = try await useCase.fetchAllFolders()
        XCTAssertEqual(renamed.first { $0.id == parent.id }?.name, "업무 (개편)")
    }

    func testNoteFolderCascadesToNullOnFolderDelete() async throws {
        let db = try await makeDatabase()
        let noteRepository = SQLiteNoteRepository(db: db)
        let useCases = makeUseCases(db)

        let folder = try await useCases.folders.createFolder(name: "임시", parentID: nil)
        let note = try await useCases.notes.createNote(folderID: folder.id)

        try await useCases.folders.delete(id: folder.id)

        let fetched = try await noteRepository.fetchNote(id: note.id)
        XCTAssertNotNil(fetched, "노트 자체는 남아 있어야 한다")
        XCTAssertNil(fetched?.folderID, "ON DELETE SET NULL로 folder_id가 비워져야 한다")
    }
}
