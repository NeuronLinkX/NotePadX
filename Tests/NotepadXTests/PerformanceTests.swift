import XCTest
@testable import NotepadX

/// 스펙 20절 성능 요구사항(대량 노트에서도 실사용 가능한 응답 속도)을 실제 SQLite 파일에
/// 노트 1만 개를 만들어 두고 검증한다. 목(mock) 없이 `DatabaseManager`/`SQLiteNoteRepository`/
/// `SearchIndexService`를 그대로 통과시켜, 실제 사용자가 겪을 성능에 가깝게 잰다.
final class PerformanceTests: XCTestCase {
    private var tempURL: URL!
    private static let noteCount = 10_000

    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotepadXPerfTests-\(UUID().uuidString).sqlite")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempURL)
    }

    private func makeDatabase() async throws -> DatabaseManager {
        let db = try DatabaseManager(databaseURL: tempURL)
        try await SchemaMigrator.migrate(db)
        return db
    }

    /// `NoteUseCase.createNote`/`applyEdit`/`save`를 그대로 1만 번 호출한다 — 실제 사용자가
    /// "메모 1만 개 쌓인 상태"에 이르는 것과 동일한 경로(개별 INSERT + FTS 재색인)다.
    /// 벌크 트랜잭션으로 지름길을 만들지 않는다: 그러면 이 테스트가 검증하려는, 실사용에서
    /// 실제로 겪는 building 비용을 재지 못하게 된다.
    private func seedNotes(_ noteUseCase: NoteUseCase, count: Int) async throws {
        for i in 0..<count {
            let created = try await noteUseCase.createNote(folderID: nil)
            let document = EditorDocument.fromPlainText("성능 테스트 노트 본문 \(i)번 — 검색과 목록 조회 속도를 재기 위한 더미 텍스트입니다.")
            let updated = try noteUseCase.applyEdit(
                to: created,
                title: "성능 테스트 노트 \(i)",
                document: document,
                plainText: document.derivedPlainText
            )
            try await noteUseCase.save(updated)
        }
    }

    func testBulkInsertListAndSearchPerformanceAtTenThousandNotes() async throws {
        let db = try await makeDatabase()
        let noteRepo = SQLiteNoteRepository(db: db)
        let searchIndex = SearchIndexService(db: db)
        let noteUseCase = NoteUseCase(noteRepository: noteRepo, searchIndex: searchIndex)
        let searchUseCase = SearchUseCase(searchIndex: searchIndex)

        let insertStart = ContinuousClock.now
        try await seedNotes(noteUseCase, count: Self.noteCount)
        let insertElapsed = insertStart.duration(to: .now)

        let count = try await db.query("SELECT COUNT(*) FROM note;") { $0.int(0) ?? 0 }.first ?? 0
        XCTAssertEqual(count, Self.noteCount)

        let listStart = ContinuousClock.now
        let all = try await noteUseCase.fetchNotes(filter: .all, sortOrder: .updatedDescending)
        let listElapsed = listStart.duration(to: .now)
        XCTAssertEqual(all.count, Self.noteCount)

        let searchStart = ContinuousClock.now
        let hits = try await searchUseCase.search(query: "5000번")
        let searchElapsed = searchStart.duration(to: .now)
        XCTAssertFalse(hits.isEmpty)

        let recentStart = ContinuousClock.now
        _ = try await noteUseCase.fetchNotes(filter: .recent, sortOrder: .updatedDescending)
        let recentElapsed = recentStart.duration(to: .now)

        report(
            """
            [성능 벤치마크] 노트 \(Self.noteCount)개
              전체 생성(개별 INSERT + FTS 재색인 \(Self.noteCount)회): \(insertElapsed)
              전체 목록 조회(fetchNotes .all, \(all.count)건): \(listElapsed)
              FTS5 검색 1회("5000번", \(hits.count)건 일치): \(searchElapsed)
              최근 목록 조회(.recent): \(recentElapsed)
            """
        )

        // 절대적인 기준(예: "5초 이내")은 CI 머신마다 편차가 커서 스스로 실패하는 flaky 테스트가
        // 되기 쉽다. 대신 "노트 1개 처리에 평균 200ms를 넘지 않는다"처럼 넉넉한 상한만 걸어서
        // 회귀(예: 실수로 인덱스를 없애거나 N+1 쿼리를 추가하는 경우)를 잡는 안전망으로 쓴다.
        XCTAssertLessThan(insertElapsed, .seconds(Self.noteCount) / 5, "노트 생성이 비정상적으로 느려짐 (평균 200ms/건 초과)")
        XCTAssertLessThan(listElapsed, .seconds(5), "전체 목록 조회가 비정상적으로 느려짐")
        XCTAssertLessThan(searchElapsed, .seconds(2), "FTS5 검색이 비정상적으로 느려짐")
    }

    /// 목록/검색과 달리 태그 부여는 노트당 여러 JOIN 테이블 갱신이 필요해서 별도로 잰다.
    func testTagAssignmentPerformanceAtScale() async throws {
        let db = try await makeDatabase()
        let noteRepo = SQLiteNoteRepository(db: db)
        let searchIndex = SearchIndexService(db: db)
        let noteUseCase = NoteUseCase(noteRepository: noteRepo, searchIndex: searchIndex)
        let tagUseCase = TagUseCase(tagRepository: SQLiteTagRepository(db: db), searchIndex: searchIndex)

        let sampleCount = 1_000
        try await seedNotes(noteUseCase, count: sampleCount)
        let notes = try await noteUseCase.fetchNotes(filter: .all, sortOrder: .updatedDescending)

        let tag = try await tagUseCase.findOrCreateTag(name: "성능태그")

        let start = ContinuousClock.now
        for note in notes {
            try await tagUseCase.setTags(noteID: note.id, tagIDs: [tag.id])
        }
        let elapsed = start.duration(to: .now)

        report("[성능 벤치마크] 노트 \(sampleCount)개에 태그 부여: \(elapsed)")
        XCTAssertLessThan(elapsed, .seconds(sampleCount) / 5, "태그 부여가 비정상적으로 느려짐 (평균 200ms/건 초과)")
    }

    private func report(_ message: String) {
        // XCTest 결과 로그에 그대로 남도록 XCTContext 대신 print를 쓴다 — CI 콘솔에서 바로 보인다.
        print(message)
    }
}
