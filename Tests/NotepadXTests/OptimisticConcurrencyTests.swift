import XCTest
@testable import NotepadX

/// 분할 편집에서 같은 노트를 두 패널이 동시에 열었을 때, 한쪽 저장이 다른 쪽을
/// 조용히 덮어쓰지 않는지 검증한다 (스펙 9절).
final class OptimisticConcurrencyTests: XCTestCase {
    private var tempURL: URL!

    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotepadXConcurrencyTests-\(UUID().uuidString).sqlite")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempURL)
    }

    private func makeUseCase() async throws -> (repo: SQLiteNoteRepository, useCase: NoteUseCase) {
        let db = try DatabaseManager(databaseURL: tempURL)
        try await SchemaMigrator.migrate(db)
        let repo = SQLiteNoteRepository(db: db)
        let index = SearchIndexService(db: db)
        return (repo, NoteUseCase(noteRepository: repo, searchIndex: index))
    }

    func testSecondSaveWithStaleTimestampIsRejected() async throws {
        let stack = try await makeUseCase()
        let note = try await stack.useCase.createNote(folderID: nil)
        let originalUpdatedAt = note.updatedAt

        // 패널 A: 저장 성공 (기준 시각이 DB와 일치).
        let editedByPaneA = try stack.useCase.applyEdit(
            to: note, title: "A가 쓴 제목", document: .fromPlainText("A 내용"), plainText: "A 내용"
        )
        let paneASucceeded = try await stack.useCase.saveIfUnchanged(editedByPaneA, expectedUpdatedAt: originalUpdatedAt)
        XCTAssertTrue(paneASucceeded)

        // 패널 B: A의 저장을 모른 채 같은 원본(originalUpdatedAt)을 기준으로 저장 시도 → 거부되어야 한다.
        let editedByPaneB = try stack.useCase.applyEdit(
            to: note, title: "B가 쓴 제목", document: .fromPlainText("B 내용"), plainText: "B 내용"
        )
        let paneBSucceeded = try await stack.useCase.saveIfUnchanged(editedByPaneB, expectedUpdatedAt: originalUpdatedAt)
        XCTAssertFalse(paneBSucceeded, "다른 패널이 먼저 저장했으면 두 번째 저장은 조용히 성공하면 안 된다")

        // DB에는 A의 내용만 남아 있어야 한다 (B의 저장 시도로 조용히 덮어써지지 않음).
        let fetched = try await stack.repo.fetchNote(id: note.id)
        XCTAssertEqual(fetched?.plainText, "A 내용")
    }

    func testSaveSucceedsAfterReloadingLatestTimestamp() async throws {
        let stack = try await makeUseCase()
        let note = try await stack.useCase.createNote(folderID: nil)

        let editedByPaneA = try stack.useCase.applyEdit(
            to: note, title: "먼저", document: .fromPlainText("먼저 저장"), plainText: "먼저 저장"
        )
        try await stack.useCase.save(editedByPaneA)

        // 패널 B가 최신 상태를 다시 불러온 뒤(새로고침) 저장하면 성공해야 한다.
        guard let latest = try await stack.repo.fetchNote(id: note.id) else {
            return XCTFail("노트를 다시 불러오지 못했습니다")
        }
        let editedByPaneB = try stack.useCase.applyEdit(
            to: latest, title: "나중에", document: .fromPlainText("나중 저장"), plainText: "나중 저장"
        )
        let succeeded = try await stack.useCase.saveIfUnchanged(editedByPaneB, expectedUpdatedAt: latest.updatedAt)
        XCTAssertTrue(succeeded)
    }
}
