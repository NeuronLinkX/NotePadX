import XCTest
@testable import NotepadX

/// note.kind 컬럼(마이그레이션 v4)과 NoteUseCase.createDiagram/applyEdit(documentJSON:)가
/// 실제 SQLite를 오가며 DiagramDocument를 손실 없이 저장·복원하는지 검증한다.
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

    func testCreateDiagramPersistsDiagramKindAndEmptyDocument() async throws {
        let noteUseCase = try await makeNoteUseCase()
        let note = try await noteUseCase.createDiagram(folderID: nil)
        let reloaded = try await noteUseCase.fetchNote(id: note.id)
        XCTAssertEqual(reloaded?.kind, .diagram)
        let decoded = try JSONDecoder().decode(DiagramDocument.self, from: reloaded?.documentJSON ?? Data())
        XCTAssertTrue(decoded.shapes.isEmpty)
    }

    func testApplyEditWithDiagramJSONRoundTripsShapesAndPlainText() async throws {
        let noteUseCase = try await makeNoteUseCase()
        let note = try await noteUseCase.createDiagram(folderID: nil)

        var document = DiagramDocument()
        document.shapes = [DiagramShape(kind: .rectangle, center: .init(x: 10, y: 20), width: 100, height: 50, text: "노드", fillColorHex: "#FFFFFFFF", strokeColorHex: "#000000FF")]
        let data = try JSONEncoder().encode(document)
        let updated = noteUseCase.applyEdit(to: note, title: "내 다이어그램", documentJSON: data, plainText: document.derivedPlainText)
        try await noteUseCase.save(updated)

        let reloaded = try await noteUseCase.fetchNote(id: note.id)
        XCTAssertEqual(reloaded?.title, "내 다이어그램")
        XCTAssertEqual(reloaded?.plainText, "노드")
        XCTAssertEqual(reloaded?.kind, .diagram)
        let decoded = try JSONDecoder().decode(DiagramDocument.self, from: reloaded?.documentJSON ?? Data())
        XCTAssertEqual(decoded, document)
    }

    func testFetchNotesIncludesBothTextAndDiagramNotes() async throws {
        let noteUseCase = try await makeNoteUseCase()
        _ = try await noteUseCase.createNote(folderID: nil)
        _ = try await noteUseCase.createDiagram(folderID: nil)

        let all = try await noteUseCase.fetchNotes(filter: .all)
        XCTAssertEqual(Set(all.map(\.kind)), [.text, .diagram])
    }
}
