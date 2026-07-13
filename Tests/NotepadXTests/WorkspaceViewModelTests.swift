import XCTest
@testable import NotepadX

@MainActor
final class WorkspaceViewModelTests: XCTestCase {
    private var tempURL: URL!

    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotepadXWorkspaceTests-\(UUID().uuidString).sqlite")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempURL)
        UserDefaults.standard.removeObject(forKey: "NotepadX.splitRatio")
    }

    private func makeWorkspace() async throws -> WorkspaceViewModel {
        let db = try DatabaseManager(databaseURL: tempURL)
        try await SchemaMigrator.migrate(db)
        let index = SearchIndexService(db: db)
        let noteUseCase = NoteUseCase(noteRepository: SQLiteNoteRepository(db: db), searchIndex: index)
        let tagUseCase = TagUseCase(tagRepository: SQLiteTagRepository(db: db), searchIndex: index)
        let revisionUseCase = NoteRevisionUseCase(
            revisionRepository: SQLiteNoteRevisionRepository(db: db),
            noteRepository: SQLiteNoteRepository(db: db)
        )
        return WorkspaceViewModel(noteUseCase: noteUseCase, tagUseCase: tagUseCase, revisionUseCase: revisionUseCase)
    }

    func testTogglingSplitStartsWithSameDocumentInBothPanes() async throws {
        let workspace = try await makeWorkspace()
        XCTAssertEqual(workspace.splitMode, .none)

        let primaryNoteID = UUID()
        workspace.toggleHorizontalSplit(primaryNoteID: primaryNoteID)

        XCTAssertEqual(workspace.splitMode, .horizontal)
        XCTAssertEqual(workspace.secondaryNoteID, primaryNoteID, "분할을 처음 켤 때는 같은 문서를 양쪽에 띄워야 한다")
    }

    func testTogglingSameModeTwiceClosesTheSplit() async throws {
        let workspace = try await makeWorkspace()
        workspace.toggleVerticalSplit(primaryNoteID: UUID())
        XCTAssertEqual(workspace.splitMode, .vertical)

        workspace.toggleVerticalSplit(primaryNoteID: UUID())
        XCTAssertEqual(workspace.splitMode, .none)
    }

    func testReopeningSplitAfterCloseResetsToSameDocument() async throws {
        let workspace = try await makeWorkspace()
        let primaryNoteID = UUID()
        workspace.toggleHorizontalSplit(primaryNoteID: primaryNoteID)
        workspace.secondaryNoteID = UUID() // 사용자가 오른쪽 패널에서 다른 문서를 골랐다고 가정
        XCTAssertNotEqual(workspace.secondaryNoteID, primaryNoteID)

        workspace.toggleHorizontalSplit(primaryNoteID: primaryNoteID) // 분할 닫기
        workspace.toggleVerticalSplit(primaryNoteID: primaryNoteID)   // 상하 분할로 새로 열기

        XCTAssertEqual(workspace.splitMode, .vertical)
        XCTAssertEqual(workspace.secondaryNoteID, primaryNoteID, "분할을 닫았다 새로 열면 다시 같은 문서로 시작해야 한다")
    }

    func testSplitRatioPersistsAcrossInstances() async throws {
        let workspace = try await makeWorkspace()
        workspace.setSplitRatio(0.7)

        let recreated = try await makeWorkspace()
        XCTAssertEqual(recreated.splitRatio, 0.7, accuracy: 0.0001)
    }

    func testCloseSplitReturnsToNone() async throws {
        let workspace = try await makeWorkspace()
        workspace.toggleHorizontalSplit(primaryNoteID: UUID())
        workspace.closeSplit()
        XCTAssertEqual(workspace.splitMode, .none)
    }
}
