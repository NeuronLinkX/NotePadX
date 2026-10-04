import XCTest
@testable import NotepadX

final class WidgetSnapshotTests: XCTestCase {
    private var tempURL: URL!
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotepadXWidgetTests-\(UUID().uuidString).sqlite")
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotepadXWidgetSnapshot-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    private func makeDatabase() async throws -> (DatabaseManager, NoteUseCase) {
        let db = try DatabaseManager(databaseURL: tempURL)
        try await SchemaMigrator.migrate(db)
        let noteUseCase = NoteUseCase(noteRepository: SQLiteNoteRepository(db: db), searchIndex: SearchIndexService(db: db))
        return (db, noteUseCase)
    }

    private func saveNote(_ useCase: NoteUseCase, title: String, body: String, updatedAt: Date, pinned: Bool = false, favorite: Bool = false) async throws -> Note {
        var note = try await useCase.createNote(folderID: nil)
        note = useCase.applyEdit(to: note, title: title, documentJSON: Data("{}".utf8), plainText: body)
        note.updatedAt = updatedAt
        note.isPinned = pinned
        note.isFavorite = favorite
        try await useCase.save(note)
        return note
    }

    func testStoreRoundTripsSnapshotThroughTheSharedFile() throws {
        let snapshot = WidgetSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            notes: [WidgetNoteSummary(id: UUID(), title: "제목", preview: "미리보기", updatedAt: Date(timeIntervalSince1970: 1_700_000_100), isFavorite: true, isPinned: false)]
        )

        try WidgetSnapshotStore.write(snapshot, to: tempDirectory)

        XCTAssertEqual(WidgetSnapshotStore.read(from: tempDirectory), snapshot)
    }

    func testReadReturnsNilWhenTheAppHasNeverExported() {
        XCTAssertNil(WidgetSnapshotStore.read(from: tempDirectory))
    }

    func testDeepLinkParsesNoteAndNewURLs() {
        let id = UUID()
        XCTAssertEqual(WidgetDeepLink(url: WidgetDeepLink.url(forNote: id)), .openNote(id))
        XCTAssertEqual(WidgetDeepLink(url: WidgetDeepLink.newNoteURL), .newNote)
    }

    func testDeepLinkRejectsForeignSchemesAndMalformedIDs() {
        XCTAssertNil(WidgetDeepLink(url: URL(string: "https://example.com/note/abc")!))
        XCTAssertNil(WidgetDeepLink(url: URL(string: "notepadx://note/not-a-uuid")!))
        XCTAssertNil(WidgetDeepLink(url: URL(string: "notepadx://unknown")!))
    }

    func testSnapshotListsNewestFirstAndSkipsTrashedNotes() async throws {
        let (db, useCase) = try await makeDatabase()
        let older = try await saveNote(useCase, title: "오래된", body: "a", updatedAt: Date(timeIntervalSince1970: 1_000))
        let newer = try await saveNote(useCase, title: "최근", body: "b", updatedAt: Date(timeIntervalSince1970: 2_000))
        let trashed = try await saveNote(useCase, title: "삭제됨", body: "c", updatedAt: Date(timeIntervalSince1970: 3_000))
        try await useCase.moveToTrash(id: trashed.id)

        let snapshot = try await WidgetSnapshotService.makeSnapshot(from: db)

        XCTAssertEqual(snapshot.notes.map(\.id), [newer.id, older.id])
    }

    func testPinnedNotesComeFirstAndLimitIsApplied() async throws {
        let (db, useCase) = try await makeDatabase()
        let pinned = try await saveNote(useCase, title: "고정", body: "p", updatedAt: Date(timeIntervalSince1970: 100), pinned: true)
        for index in 1...4 {
            _ = try await saveNote(useCase, title: "메모 \(index)", body: "x", updatedAt: Date(timeIntervalSince1970: 1_000 + Double(index)))
        }

        let snapshot = try await WidgetSnapshotService.makeSnapshot(from: db, limit: 3)

        XCTAssertEqual(snapshot.notes.count, 3)
        XCTAssertEqual(snapshot.notes.first?.id, pinned.id, "오래됐어도 고정된 메모는 맨 앞에 와야 한다")
    }

    func testEmptyTitleFallsBackAndPreviewIsCollapsedAndTruncated() async throws {
        let (db, useCase) = try await makeDatabase()
        let longBody = String(repeating: "가", count: 300)
        _ = try await saveNote(useCase, title: "   ", body: "첫 줄\n둘째 줄 \(longBody)", updatedAt: Date())

        let note = try await WidgetSnapshotService.makeSnapshot(from: db).notes.first

        XCTAssertEqual(note?.title, "제목 없음")
        XCTAssertFalse(note?.preview.contains("\n") ?? true)
        XCTAssertTrue(note?.preview.hasPrefix("첫 줄 둘째 줄") ?? false)
        XCTAssertLessThanOrEqual(note?.preview.count ?? 0, 121)
    }
}
