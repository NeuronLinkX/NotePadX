import XCTest
@testable import NotepadX

/// note.kind 컬럼(마이그레이션 v4)과 NoteUseCase.createDiagram/applyEdit(documentJSON:)가
/// 실제 SQLite를 오가며 SVG 뷰어 노트(원문 SVG 텍스트를 documentJSON에 그대로 담는다)를
/// 손실 없이 저장·복원하는지 검증한다.
final class DiagramNotePersistenceTests: XCTestCase {
    private var tempURL: URL!

    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotepadXDiagramPersistenceTests-\(UUID().uuidString).sqlite")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempURL)
    }

    private func makeNoteUseCase() async throws -> NoteUseCase {
        let db = try DatabaseManager(databaseURL: tempURL)
        try await SchemaMigrator.migrate(db)
        let index = SearchIndexService(db: db)
        return NoteUseCase(noteRepository: SQLiteNoteRepository(db: db), searchIndex: index)
    }

    func testCreateNoteDefaultsToTextKind() async throws {
        let noteUseCase = try await makeNoteUseCase()
        let note = try await noteUseCase.createNote(folderID: nil)
        let reloaded = try await noteUseCase.fetchNote(id: note.id)
        XCTAssertEqual(reloaded?.kind, .text)
    }

    func testCreateDiagramPersistsDiagramKindWithEmptyContent() async throws {
        let noteUseCase = try await makeNoteUseCase()
        let note = try await noteUseCase.createDiagram(folderID: nil)
        let reloaded = try await noteUseCase.fetchNote(id: note.id)
        XCTAssertEqual(reloaded?.kind, .diagram)
        XCTAssertEqual(reloaded?.documentJSON, Data())
    }

    func testApplyEditWithSVGTextRoundTrips() async throws {
        let noteUseCase = try await makeNoteUseCase()
        let note = try await noteUseCase.createDiagram(folderID: nil)

        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\"><rect width=\"10\" height=\"10\"/></svg>"
        let data = Data(svg.utf8)
        let updated = noteUseCase.applyEdit(to: note, title: "불러온 SVG", documentJSON: data, plainText: "")
        try await noteUseCase.save(updated)

        let reloaded = try await noteUseCase.fetchNote(id: note.id)
        XCTAssertEqual(reloaded?.title, "불러온 SVG")
        XCTAssertEqual(reloaded?.kind, .diagram)
        XCTAssertEqual(reloaded.flatMap { String(data: $0.documentJSON, encoding: .utf8) }, svg)
    }

    func testFetchNotesIncludesBothTextAndDiagramNotes() async throws {
        let noteUseCase = try await makeNoteUseCase()
        _ = try await noteUseCase.createNote(folderID: nil)
        _ = try await noteUseCase.createDiagram(folderID: nil)

        let all = try await noteUseCase.fetchNotes(filter: .all)
        XCTAssertEqual(Set(all.map(\.kind)), [.text, .diagram])
    }
}
