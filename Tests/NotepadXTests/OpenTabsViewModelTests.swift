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
