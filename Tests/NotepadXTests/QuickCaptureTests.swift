import XCTest
@testable import NotepadX

final class QuickCaptureTests: XCTestCase {
    func testFirstNonEmptyLineBecomesTheTitleAndTheRestTheBody() {
        let parts = QuickCaptureService.split("\n  장보기 목록  \n우유\n달걀\n\n")
        XCTAssertEqual(parts?.title, "장보기 목록")
        XCTAssertEqual(parts?.body, "우유\n달걀", "끝의 빈 줄은 잘라낸다")
    }

    func testSingleLineBecomesATitleOnlyNote() {
        let parts = QuickCaptureService.split("전화하기")
        XCTAssertEqual(parts?.title, "전화하기")
        XCTAssertEqual(parts?.body, "")
    }

    func testBlankInputIsRejected() {
        XCTAssertNil(QuickCaptureService.split(""))
        XCTAssertNil(QuickCaptureService.split("   \n\t \n"))
    }

    func testWindowsLineEndingsAreHandled() {
        let parts = QuickCaptureService.split("제목\r\n본문1\r\n본문2")
        XCTAssertEqual(parts?.title, "제목")
        XCTAssertEqual(parts?.body, "본문1\n본문2")
    }

    func testOverlongFirstLineIsTruncatedButNoTextIsLost() {
        let long = String(repeating: "가", count: 120)
        let parts = QuickCaptureService.split(long + "\n다음 줄")
        XCTAssertEqual(parts?.title.count, QuickCaptureService.maxTitleLength + 1)   // + "…"
        XCTAssertTrue(parts?.title.hasSuffix("…") ?? false)
        XCTAssertTrue(parts?.body.hasPrefix(long) ?? false, "잘린 제목의 전체 내용은 본문에 남아야 한다")
        XCTAssertTrue(parts?.body.hasSuffix("다음 줄") ?? false)
    }

    func testSavingCreatesAFindableNoteAndNotifiesTheList() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("NotepadXQuick-\(UUID().uuidString).sqlite")
        defer { for s in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + s) } }
        let db = try DatabaseManager(databaseURL: url)
        try await SchemaMigrator.migrate(db)
        let index = SearchIndexService(db: db)
        let useCase = NoteUseCase(noteRepository: SQLiteNoteRepository(db: db), searchIndex: index)
        let notified = expectation(forNotification: .notesChangedExternally, object: nil)

        let note = try await QuickCaptureService(noteUseCase: useCase).save(text: "회의 메모\n안건 세 가지")

        await fulfillment(of: [notified], timeout: 2)
        XCTAssertEqual(note?.title, "회의 메모")
        let reloaded = try await useCase.fetchNote(id: XCTUnwrap(note).id)
        XCTAssertEqual(reloaded?.plainText, "안건 세 가지")
        let hits = try await SearchUseCase(searchIndex: index).search(query: "안건 세 가지", filters: SearchFilters())
        XCTAssertEqual(hits.count, 1, "저장한 메모는 바로 검색돼야 한다")
        let empty = try await QuickCaptureService(noteUseCase: useCase).save(text: "  \n ")
        XCTAssertNil(empty)
        let total = try await useCase.fetchNotes(filter: .all).count
        XCTAssertEqual(total, 1, "빈 입력은 메모를 만들지 않는다")
    }
}
