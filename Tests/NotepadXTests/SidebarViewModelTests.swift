import XCTest
@testable import NotepadX

@MainActor
final class SidebarViewModelTests: XCTestCase {
    private var tempURL: URL!

    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotepadXSidebarTests-\(UUID().uuidString).sqlite")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempURL)
    }

    private func makeViewModel() async throws -> (sidebar: SidebarViewModel, tagUseCase: TagUseCase) {
        let db = try DatabaseManager(databaseURL: tempURL)
        try await SchemaMigrator.migrate(db)
        let index = SearchIndexService(db: db)
        let folderUseCase = FolderUseCase(
            folderRepository: SQLiteFolderRepository(db: db),
            noteRepository: SQLiteNoteRepository(db: db),
            searchIndex: index
        )
        let tagUseCase = TagUseCase(tagRepository: SQLiteTagRepository(db: db), searchIndex: index)
        let sidebar = SidebarViewModel(folderUseCase: folderUseCase, tagUseCase: tagUseCase)
        return (sidebar, tagUseCase)
    }

    /// 편집기 안에서 만든 새 태그가 EditorViewModel.onTagsChanged → SidebarViewModel.refreshTags()로
    /// 이어져서 사이드바 목록에 즉시 나타나는지 확인한다 — `load()`를 다시 호출하지 않고도.
    func testRefreshTagsPicksUpTagCreatedElsewhereWithoutFullReload() async throws {
        let (sidebar, tagUseCase) = try await makeViewModel()
        await sidebar.load()
        XCTAssertTrue(sidebar.tags.isEmpty)

        // 편집기가 만들었다고 가정 — sidebar와 무관한 경로로 태그를 만든다.
        _ = try await tagUseCase.createTag(name: "회의록")

        await sidebar.refreshTags()

        XCTAssertEqual(sidebar.tags.map(\.name), ["회의록"])
    }

    func testRefreshTagsDoesNotTouchFolders() async throws {
        let (sidebar, _) = try await makeViewModel()
        await sidebar.createFolder(name: "업무", parentID: nil)
        XCTAssertEqual(sidebar.folders.count, 1)

        await sidebar.refreshTags()

        XCTAssertEqual(sidebar.folders.count, 1, "refreshTags()는 태그만 다시 불러와야 한다")
    }
}
