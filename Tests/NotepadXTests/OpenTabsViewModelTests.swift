import XCTest
@testable import NotepadX

@MainActor
final class OpenTabsViewModelTests: XCTestCase {
    private var tempURL: URL!

    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotepadXOpenTabsTests-\(UUID().uuidString).sqlite")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempURL)
    }

    private func makeTabs() async throws -> (OpenTabsViewModel, NoteUseCase) {
        let db = try DatabaseManager(databaseURL: tempURL)
        try await SchemaMigrator.migrate(db)
        let index = SearchIndexService(db: db)
        let noteUseCase = NoteUseCase(noteRepository: SQLiteNoteRepository(db: db), searchIndex: index)
        return (OpenTabsViewModel(noteUseCase: noteUseCase), noteUseCase)
    }

    func testNoteOpenedAddsANewTabOnlyOnce() async throws {
        let (tabs, _) = try await makeTabs()
        let id = UUID()

        tabs.noteOpened(id, knownTitle: "첫 메모")
        tabs.noteOpened(id, knownTitle: "첫 메모")

        XCTAssertEqual(tabs.openNoteIDs, [id])
        XCTAssertEqual(tabs.titles[id], "첫 메모")
    }

    func testNoteOpenedWithoutKnownTitleFetchesItFromNoteUseCase() async throws {
        let (tabs, noteUseCase) = try await makeTabs()
        let note = try await noteUseCase.createNote(folderID: nil)

        tabs.noteOpened(note.id)

        let deadline = Date().addingTimeInterval(2)
        while tabs.titles[note.id] == nil, Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertEqual(tabs.titles[note.id], note.displayTitle)
    }

    func testClosingTheActiveTabActivatesTheNeighborToTheLeft() async throws {
        let (tabs, _) = try await makeTabs()
        let a = UUID(), b = UUID(), c = UUID()
        tabs.noteOpened(a, knownTitle: "A")
        tabs.noteOpened(b, knownTitle: "B")
        tabs.noteOpened(c, knownTitle: "C")

        let next = tabs.closeTab(c, activeNoteID: c)

        XCTAssertEqual(next, b, "마지막 탭을 닫으면 바로 왼쪽 탭이 활성화되어야 한다")
        XCTAssertEqual(tabs.openNoteIDs, [a, b])
        XCTAssertNil(tabs.titles[c], "닫은 탭의 제목 캐시도 정리되어야 한다")
    }

    func testClosingTheLastRemainingTabLeavesNoActiveTab() async throws {
        let (tabs, _) = try await makeTabs()
        let id = UUID()
        tabs.noteOpened(id, knownTitle: "Only")

        let next = tabs.closeTab(id, activeNoteID: id)

        XCTAssertNil(next)
        XCTAssertTrue(tabs.openNoteIDs.isEmpty)
    }

    func testClosingANonActiveTabDoesNotChangeTheActiveNoteID() async throws {
        let (tabs, _) = try await makeTabs()
        let a = UUID(), b = UUID()
        tabs.noteOpened(a, knownTitle: "A")
        tabs.noteOpened(b, knownTitle: "B")

        let next = tabs.closeTab(a, activeNoteID: b)

        XCTAssertEqual(next, b, "활성 탭이 아닌 다른 탭을 닫아도 활성 탭은 그대로여야 한다")
        XCTAssertEqual(tabs.openNoteIDs, [b])
    }

    func testMoveTabReordersOpenNoteIDs() async throws {
        let (tabs, _) = try await makeTabs()
        let a = UUID(), b = UUID(), c = UUID()
        tabs.noteOpened(a, knownTitle: "A")
        tabs.noteOpened(b, knownTitle: "B")
        tabs.noteOpened(c, knownTitle: "C")

        tabs.moveTab(from: 0, to: 2)

        XCTAssertEqual(tabs.openNoteIDs, [b, c, a])
    }

    func testMoveTabClampsDestinationToValidRange() async throws {
        let (tabs, _) = try await makeTabs()
        let a = UUID(), b = UUID()
        tabs.noteOpened(a, knownTitle: "A")
        tabs.noteOpened(b, knownTitle: "B")

        tabs.moveTab(from: 0, to: 99)

        XCTAssertEqual(tabs.openNoteIDs, [b, a])
    }

    func testNeighborWrapsAroundBothEnds() async throws {
        let (tabs, _) = try await makeTabs()
        let a = UUID(), b = UUID(), c = UUID()
        tabs.noteOpened(a, knownTitle: "A")
        tabs.noteOpened(b, knownTitle: "B")
        tabs.noteOpened(c, knownTitle: "C")

        XCTAssertEqual(tabs.neighbor(of: a, offset: 1), b)
        XCTAssertEqual(tabs.neighbor(of: c, offset: 1), a, "마지막 탭에서 다음은 첫 탭")
        XCTAssertEqual(tabs.neighbor(of: a, offset: -1), c, "첫 탭에서 이전은 마지막 탭")
    }

    func testNeighborFallsBackToFirstTabWhenCurrentIsUnknown() async throws {
        let (tabs, _) = try await makeTabs()
        XCTAssertNil(tabs.neighbor(of: UUID(), offset: 1), "탭이 없으면 nil")
        let a = UUID(), b = UUID()
        tabs.noteOpened(a, knownTitle: "A")
        tabs.noteOpened(b, knownTitle: "B")

        XCTAssertEqual(tabs.neighbor(of: nil, offset: 1), a)
        XCTAssertEqual(tabs.neighbor(of: UUID(), offset: -1), a)
    }

    func testTabWidthShrinksWithCountButStaysWithinBounds() {
        XCTAssertEqual(EditorTabBarView.tabWidth(count: 1, available: 1200), EditorTabBarView.maxTabWidth)
        let five = EditorTabBarView.tabWidth(count: 5, available: 700)
        XCTAssertLessThan(five, EditorTabBarView.maxTabWidth)
        XCTAssertGreaterThanOrEqual(five, EditorTabBarView.minTabWidth)
        XCTAssertEqual(EditorTabBarView.tabWidth(count: 40, available: 700), EditorTabBarView.minTabWidth, "너무 많으면 최소폭에서 멈추고 스크롤")
    }

    func testUpdateTitleOnlyAppliesToTabsThatAreStillOpen() async throws {
        let (tabs, _) = try await makeTabs()
        let openID = UUID()
        let closedID = UUID()
        tabs.noteOpened(openID, knownTitle: "원래 제목")

        tabs.updateTitle(openID, title: "바뀐 제목")
        tabs.updateTitle(closedID, title: "탭에 없는 노트")

        XCTAssertEqual(tabs.titles[openID], "바뀐 제목")
        XCTAssertNil(tabs.titles[closedID])
    }
}

@MainActor
final class OpenTabsRestoreTests: XCTestCase {
    private var tempURL: URL!
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("NotepadXTabsRestore-\(UUID().uuidString).sqlite")
        suiteName = "NotepadXTabsRestore-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: tempURL.path + suffix) }
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeUseCase() async throws -> NoteUseCase {
        let db = try DatabaseManager(databaseURL: tempURL)
        try await SchemaMigrator.migrate(db)
        return NoteUseCase(noteRepository: SQLiteNoteRepository(db: db), searchIndex: SearchIndexService(db: db))
    }

    func testTabsAndActiveNoteSurviveARelaunch() async throws {
        let useCase = try await makeUseCase()
        let a = try await useCase.createNote(folderID: nil)
        let b = try await useCase.createNote(folderID: nil)
        let c = try await useCase.createNote(folderID: nil)

        let session1 = OpenTabsViewModel(noteUseCase: useCase, defaults: defaults)
        [a, b, c].forEach { session1.noteOpened($0.id, knownTitle: $0.displayTitle) }
        session1.moveTab(from: 2, to: 0)          // 순서 변경도 기억돼야 한다
        session1.rememberActive(b.id)

        let session2 = OpenTabsViewModel(noteUseCase: useCase, defaults: defaults)
        // 앱이 켜지면서 첫 메모가 자동 선택돼 탭 목록을 덮어쓰는 상황을 흉내 낸다.
        session2.noteOpened(a.id, knownTitle: "자동 선택")
        let active = await session2.restore()

        XCTAssertEqual(session2.openNoteIDs, [c.id, a.id, b.id])
        XCTAssertEqual(active, b.id)
    }

    func testDeletedAndTrashedNotesAreSkippedOnRestore() async throws {
        let useCase = try await makeUseCase()
        let keep = try await useCase.createNote(folderID: nil)
        let trashed = try await useCase.createNote(folderID: nil)
        let session1 = OpenTabsViewModel(noteUseCase: useCase, defaults: defaults)
        session1.noteOpened(trashed.id, knownTitle: "t")
        session1.noteOpened(keep.id, knownTitle: "k")
        session1.noteOpened(UUID(), knownTitle: "존재하지 않음")
        session1.rememberActive(trashed.id)
        try await useCase.moveToTrash(id: trashed.id)

        let session2 = OpenTabsViewModel(noteUseCase: useCase, defaults: defaults)
        let active = await session2.restore()

        XCTAssertEqual(session2.openNoteIDs, [keep.id])
        XCTAssertEqual(active, keep.id, "마지막에 보던 메모가 사라졌으면 첫 탭으로")
    }

    func testRestoreWithNothingSavedReturnsNilAndLeavesTabsAlone() async throws {
        let useCase = try await makeUseCase()
        let session = OpenTabsViewModel(noteUseCase: useCase, defaults: defaults)
        let active = await session.restore()
        XCTAssertNil(active)
        XCTAssertTrue(session.openNoteIDs.isEmpty)
    }

    func testRememberActiveIgnoresNilSoTheSavedTabIsNotLost() async throws {
        let useCase = try await makeUseCase()
        let note = try await useCase.createNote(folderID: nil)
        let session1 = OpenTabsViewModel(noteUseCase: useCase, defaults: defaults)
        session1.noteOpened(note.id, knownTitle: "x")
        session1.rememberActive(note.id)
        session1.rememberActive(nil)   // 시작 직후 잠깐 선택 없음

        let session2 = OpenTabsViewModel(noteUseCase: useCase, defaults: defaults)
        let active = await session2.restore()
        XCTAssertEqual(active, note.id)
    }
}
