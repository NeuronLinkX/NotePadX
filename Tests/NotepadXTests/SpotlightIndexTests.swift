import CoreSpotlight
import XCTest
@testable import NotepadX

final class SpotlightIndexTests: XCTestCase {
    private var tempURL: URL!

    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("NotepadXSpotlight-\(UUID().uuidString).sqlite")
    }

    override func tearDownWithError() throws {
        for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: tempURL.path + suffix) }
    }

    private func makeStack() async throws -> (DatabaseManager, NoteUseCase) {
        let db = try DatabaseManager(databaseURL: tempURL)
        try await SchemaMigrator.migrate(db)
        return (db, NoteUseCase(noteRepository: SQLiteNoteRepository(db: db), searchIndex: SearchIndexService(db: db)))
    }

    private func addNote(_ useCase: NoteUseCase, title: String, body: String) async throws -> Note {
        var note = try await useCase.createNote(folderID: nil)
        note = useCase.applyEdit(to: note, title: title, documentJSON: Data("{}".utf8), plainText: body)
        try await useCase.save(note)
        return note
    }

    func testOnlyVisibleNotesAreIndexed() async throws {
        let (db, useCase) = try await makeStack()
        let normal = try await addNote(useCase, title: "일반", body: "공개 본문")
        let locked = try await addNote(useCase, title: "비밀", body: "잠긴 본문")
        let trashed = try await addNote(useCase, title: "삭제", body: "버린 본문")
        try await useCase.setLocked(id: locked.id, isLocked: true)
        try await useCase.moveToTrash(id: trashed.id)

        let rows = try await SpotlightIndexService.rows(from: db)

        XCTAssertEqual(rows.map(\.id), [normal.id], "잠긴 메모와 휴지통 메모는 Spotlight에 넣지 않는다")
        XCTAssertEqual(rows.first?.preview, "공개 본문")
    }

    func testItemsCarryTitleAndOptionalPreview() {
        let row = SpotlightIndexService.Row(id: UUID(), title: "병원 예약", preview: "민감한 내용", updatedAt: Date())

        let withPreview = SpotlightIndexService.makeItems(rows: [row], includePreviews: true).first
        let titleOnly = SpotlightIndexService.makeItems(rows: [row], includePreviews: false).first

        XCTAssertEqual(withPreview?.uniqueIdentifier, row.id.uuidString)
        XCTAssertEqual(withPreview?.domainIdentifier, SpotlightIndexService.domain)
        XCTAssertEqual(withPreview?.attributeSet.title, "병원 예약")
        XCTAssertEqual(withPreview?.attributeSet.contentDescription, "민감한 내용")
        XCTAssertNil(titleOnly?.attributeSet.contentDescription, "미리보기를 끄면 본문 발췌가 등록되면 안 된다")
    }

    func testBlankTitlesGetAPlaceholder() async throws {
        let (db, useCase) = try await makeStack()
        _ = try await addNote(useCase, title: "   ", body: "본문만")
        let rows = try await SpotlightIndexService.rows(from: db)
        XCTAssertEqual(rows.first?.title, "제목 없음")
    }

    func testNoteIDIsReadFromASpotlightActivityAndOtherActivitiesAreIgnored() {
        let id = UUID()
        let spotlight = NSUserActivity(activityType: CSSearchableItemActionType)
        spotlight.userInfo = [CSSearchableItemActivityIdentifier: id.uuidString]
        XCTAssertEqual(SpotlightIndexService.noteID(from: spotlight), id)

        let other = NSUserActivity(activityType: "com.example.other")
        other.userInfo = [CSSearchableItemActivityIdentifier: id.uuidString]
        XCTAssertNil(SpotlightIndexService.noteID(from: other))

        let garbage = NSUserActivity(activityType: CSSearchableItemActionType)
        garbage.userInfo = [CSSearchableItemActivityIdentifier: "not-a-uuid"]
        XCTAssertNil(SpotlightIndexService.noteID(from: garbage))
    }
}
