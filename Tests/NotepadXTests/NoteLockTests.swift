import XCTest
@testable import NotepadX

private struct FakeAuthenticator: NoteAuthenticating {
    let allow: Bool
    func authenticate(reason: String) async -> Bool { allow }
}

final class NoteLockDataTests: XCTestCase {
    private var tempURL: URL!

    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("NotepadXLock-\(UUID().uuidString).sqlite")
    }

    override func tearDownWithError() throws {
        for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: tempURL.path + suffix) }
    }

    private func makeStack() async throws -> (DatabaseManager, NoteUseCase) {
        let db = try DatabaseManager(databaseURL: tempURL)
        try await SchemaMigrator.migrate(db)
        let index = SearchIndexService(db: db)
        return (db, NoteUseCase(noteRepository: SQLiteNoteRepository(db: db), searchIndex: index))
    }

    private func makeNote(_ useCase: NoteUseCase, title: String, body: String) async throws -> Note {
        var note = try await useCase.createNote(folderID: nil)
        note = useCase.applyEdit(to: note, title: title, documentJSON: Data("{}".utf8), plainText: body)
        try await useCase.save(note)
        return note
    }

    func testLockPersistsAndAnEditorAutosaveFromAStaleCopyCannotUnlockIt() async throws {
        let (_, useCase) = try await makeStack()
        let stale = try await makeNote(useCase, title: "비밀", body: "내용")   // 편집기가 열 때 읽어 둔 복사본(잠금 아님)

        try await useCase.setLocked(id: stale.id, isLocked: true)
        try await useCase.save(useCase.applyEdit(to: stale, title: "비밀 수정", documentJSON: Data("{}".utf8), plainText: "새 내용"))

        let reloaded = try await useCase.fetchNote(id: stale.id)
        XCTAssertEqual(reloaded?.isLocked, true, "편집기 자동 저장이 잠금을 풀어 버리면 안 된다")
        XCTAssertEqual(reloaded?.title, "비밀 수정")
    }

    func testLockedNotesDoNotExposeTheirTextThroughSearchSnippets() async throws {
        let (db, useCase) = try await makeStack()
        let search = SearchUseCase(searchIndex: SearchIndexService(db: db))
        let note = try await makeNote(useCase, title: "여행 일정", body: "제주 비밀계획 알파")

        let before = try await search.search(query: "비밀계획", filters: SearchFilters())
        XCTAssertEqual(before.count, 1)

        try await useCase.setLocked(id: note.id, isLocked: true)
        let bodyHits = try await search.search(query: "비밀계획", filters: SearchFilters())
        XCTAssertTrue(bodyHits.isEmpty, "잠근 뒤에는 본문 검색에 걸리면 안 된다")
        let titleHits = try await search.search(query: "여행 일정", filters: SearchFilters())
        XCTAssertEqual(titleHits.count, 1, "제목으로는 여전히 찾을 수 있다")
        XCTAssertFalse(titleHits.first?.snippet.contains("비밀계획") ?? true, "발췌문에 본문이 새면 안 된다")

        try await useCase.setLocked(id: note.id, isLocked: false)
        let restored = try await search.search(query: "비밀계획", filters: SearchFilters())
        XCTAssertEqual(restored.count, 1, "풀면 다시 본문 검색이 된다")
    }

    func testShortQueriesDoNotSearchTheBodyOfLockedNotes() async throws {
        let (db, useCase) = try await makeStack()
        let search = SearchUseCase(searchIndex: SearchIndexService(db: db))
        let note = try await makeNote(useCase, title: "일정", body: "비밀 제주")   // "제주"는 2글자 → LIKE 경로
        let before = try await search.search(query: "제주", filters: SearchFilters())
        XCTAssertEqual(before.count, 1)

        try await useCase.setLocked(id: note.id, isLocked: true)
        let after = try await search.search(query: "제주", filters: SearchFilters())
        XCTAssertTrue(after.isEmpty, "2글자 질의가 잠긴 메모의 본문을 뒤지면 내용이 추측당한다")
        let byTitle = try await search.search(query: "일정", filters: SearchFilters())
        XCTAssertEqual(byTitle.first?.snippet, "", "제목으로 찾아도 본문 발췌는 비어 있어야 한다")
    }

    func testListPreviewIsEmptyForLockedNotes() async throws {
        let (_, useCase) = try await makeStack()
        let note = try await makeNote(useCase, title: "t", body: "비밀 본문")
        let open = try await useCase.fetchNote(id: note.id)
        XCTAssertFalse(open?.previewText.isEmpty ?? true)

        try await useCase.setLocked(id: note.id, isLocked: true)
        let locked = try await useCase.fetchNote(id: note.id)
        XCTAssertEqual(locked?.previewText, "")
    }

    func testOneDriveSyncSkipsLockedNotesEntirely() async throws {
        let (db, useCase) = try await makeStack()
        let sync = OneDriveSyncUseCase(
            noteRepository: SQLiteNoteRepository(db: db),
            syncStateRepository: SQLiteSyncStateRepository(db: db),
            searchIndex: SearchIndexService(db: db),
            deviceID: "test"
        )
        let note = try await makeNote(useCase, title: "비밀", body: "클라우드로 나가면 안 됨")
        try await useCase.setLocked(id: note.id, isLocked: true)
        let provider = FakeCloudSyncProvider()

        let outcome = try await sync.sync(noteID: note.id, using: provider)

        XCTAssertEqual(outcome, .upToDate)
        let remote = try await provider.listNotes()
        XCTAssertTrue(remote.isEmpty, "잠긴 메모는 클라우드 폴더에 올라가면 안 된다")
    }

    func testWidgetSnapshotShowsLockedNotesOnlyAsAPlaceholder() async throws {
        let (db, useCase) = try await makeStack()
        let note = try await makeNote(useCase, title: "비밀 제목", body: "비밀 본문")
        try await useCase.setLocked(id: note.id, isLocked: true)

        let snapshot = try await WidgetSnapshotService.makeSnapshot(from: db)

        XCTAssertEqual(snapshot.notes.first?.title, "잠긴 메모")
        XCTAssertEqual(snapshot.notes.first?.preview, "")
    }
}

@MainActor
final class NoteLockSessionTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        suiteName = "NotepadXLockSession-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        clock = Date(timeIntervalSince1970: 1_800_000_000)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeSession(allow: Bool) -> NoteLockSession {
        NoteLockSession(authenticator: FakeAuthenticator(allow: allow), defaults: defaults, now: { [unowned self] in self.clock })
    }

    func testFailedAuthenticationNeverOpensTheNote() async {
        let session = makeSession(allow: false)
        let id = UUID()
        let ok = await session.unlock(id, reason: "x")
        XCTAssertFalse(ok)
        XCTAssertFalse(session.isUnlocked(id))
    }

    func testSuccessfulAuthenticationOpensTheNoteForThisSession() async {
        let session = makeSession(allow: true)
        let id = UUID()
        let ok = await session.unlock(id, reason: "x")
        XCTAssertTrue(ok)
        XCTAssertTrue(session.isUnlocked(id))
        session.forget(id)
        XCTAssertFalse(session.isUnlocked(id))
    }

    func testRelocksOnlyAfterTheConfiguredTimeAwayFromTheApp() async {
        let session = makeSession(allow: true)
        session.relockSeconds = 60
        let id = UUID()
        _ = await session.unlock(id, reason: "x")

        session.appDidResignActive()
        clock.addTimeInterval(30)
        session.appDidBecomeActive()
        XCTAssertTrue(session.isUnlocked(id), "잠깐(30초) 앱을 떠났다 돌아오면 그대로")

        session.appDidResignActive()
        clock.addTimeInterval(61)
        session.appDidBecomeActive()
        XCTAssertFalse(session.isUnlocked(id), "1분 넘게 떠나 있었으면 다시 잠겨야 한다")
    }

    func testImmediateRelockModeLocksTheMomentTheAppIsLeft() async {
        let session = makeSession(allow: true)
        session.relockSeconds = 0
        let id = UUID()
        _ = await session.unlock(id, reason: "x")
        session.appDidResignActive()
        XCTAssertFalse(session.isUnlocked(id))
    }

    func testNeverRelockModeKeepsNotesOpenUntilQuit() async {
        let session = makeSession(allow: true)
        session.relockSeconds = -1
        let id = UUID()
        _ = await session.unlock(id, reason: "x")
        session.appDidResignActive()
        clock.addTimeInterval(86_400)
        session.appDidBecomeActive()
        XCTAssertTrue(session.isUnlocked(id))
    }

    func testRelockSettingPersistsAndDefaultsToOneMinute() {
        XCTAssertEqual(makeSession(allow: true).relockSeconds, 60)
        let session = makeSession(allow: true)
        session.relockSeconds = 300
        XCTAssertEqual(makeSession(allow: true).relockSeconds, 300)
    }

    func testFakeAuthenticatorIsNeverChosenOutsideAnIsolatedProfile() {
        // 시험 중에는 NOTEPADX_PROFILE이 없으므로(실사용 프로필) 환경 변수가 있어도 시스템 인증기여야 한다.
        XCTAssertFalse(AppConfig.isIsolatedProfile)
        XCTAssertTrue(NoteLockSession.defaultAuthenticator() is SystemNoteAuthenticator)
    }
}
