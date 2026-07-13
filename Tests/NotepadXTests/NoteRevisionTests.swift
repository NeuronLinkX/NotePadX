import XCTest
@testable import NotepadX

final class NoteRevisionTests: XCTestCase {
    private var tempURL: URL!

    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotepadXRevisionTests-\(UUID().uuidString).sqlite")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempURL)
    }

    private func makeStack() async throws -> (notes: NoteUseCase, revisions: NoteRevisionUseCase) {
        let db = try DatabaseManager(databaseURL: tempURL)
        try await SchemaMigrator.migrate(db)
        let index = SearchIndexService(db: db)
        let noteRepo = SQLiteNoteRepository(db: db)
        let revisionRepo = SQLiteNoteRevisionRepository(db: db)
        return (
            NoteUseCase(noteRepository: noteRepo, searchIndex: index),
            NoteRevisionUseCase(revisionRepository: revisionRepo, noteRepository: noteRepo)
        )
    }

    func testSnapshotAndListRevisions() async throws {
        let stack = try await makeStack()
        let note = try await stack.notes.createNote(folderID: nil)
        try await stack.revisions.snapshot(note: note, reason: .manualSnapshot)

        let revisions = try await stack.revisions.revisions(forNote: note.id)
        XCTAssertEqual(revisions.count, 1)
        XCTAssertEqual(revisions.first?.reason, .manualSnapshot)
    }

    func testPruneKeepsOnlyMostRecentRevisions() async throws {
        let stack = try await makeStack()
        let note = try await stack.notes.createNote(folderID: nil)

        for i in 0..<25 {
            let edited = try stack.notes.applyEdit(to: note, title: "제목\(i)", document: .fromPlainText("본문\(i)"), plainText: "본문\(i)")
            try await stack.revisions.snapshot(note: edited, reason: .periodicEdit)
        }

        let revisions = try await stack.revisions.revisions(forNote: note.id)
        XCTAssertEqual(revisions.count, NoteRevisionUseCase.defaultKeepCount)
    }

    func testRestoreAppliesOldContentAndArchivesCurrent() async throws {
        let stack = try await makeStack()
        let note = try await stack.notes.createNote(folderID: nil)

        let v1 = try stack.notes.applyEdit(to: note, title: "버전1", document: .fromPlainText("첫 번째 내용"), plainText: "첫 번째 내용")
        try await stack.notes.save(v1)
        let snapshot = try await stack.revisions.snapshot(note: v1, reason: .manualSnapshot)

        let v2 = try stack.notes.applyEdit(to: v1, title: "버전2", document: .fromPlainText("두 번째 내용"), plainText: "두 번째 내용")
        try await stack.notes.save(v2)

        let restored = try await stack.revisions.restore(revisionID: snapshot.id)
        XCTAssertEqual(restored.plainText, "첫 번째 내용")

        // 복원 전 "두 번째 내용" 상태가 자동으로 리비전에 보관되어야 한다.
        let revisions = try await stack.revisions.revisions(forNote: note.id)
        XCTAssertTrue(revisions.contains { $0.plainText == "두 번째 내용" && $0.reason == .beforeRestore })
    }
}
