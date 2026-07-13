import XCTest
@testable import NotepadX

/// 노트에 태그를 붙이는 전체 경로(EditorViewModel → TagUseCase → SQLite)를 검증한다.
/// `TagChipsView`의 "새 태그 만들기" 버튼이 한때 Task{} 실행 전에 입력값을 지워버려
/// 항상 빈 이름("새 태그")으로 생성되던 버그가 있었다 — 그건 View 레이어의 클로저 캡처
/// 순서 문제였지만, 여기서는 EditorViewModel이 실제로 넘겨받은 이름으로 정확히 태그를
/// 만들고 붙이는지를 고정해서 같은 종류의 회귀를 잡는다.
@MainActor
final class EditorViewModelTagTests: XCTestCase {
    private var tempURL: URL!

    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotepadXEditorTagTests-\(UUID().uuidString).sqlite")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempURL)
    }

    private func makeEnvironment() async throws -> (editor: EditorViewModel, tagUseCase: TagUseCase, noteID: UUID) {
        let db = try DatabaseManager(databaseURL: tempURL)
        try await SchemaMigrator.migrate(db)
        let index = SearchIndexService(db: db)
        let noteUseCase = NoteUseCase(noteRepository: SQLiteNoteRepository(db: db), searchIndex: index)
        let tagUseCase = TagUseCase(tagRepository: SQLiteTagRepository(db: db), searchIndex: index)
        let revisionUseCase = NoteRevisionUseCase(
            revisionRepository: SQLiteNoteRevisionRepository(db: db),
            noteRepository: SQLiteNoteRepository(db: db)
        )
        let created = try await noteUseCase.createNote(folderID: nil)
        let editor = EditorViewModel(noteUseCase: noteUseCase, tagUseCase: tagUseCase, revisionUseCase: revisionUseCase)
        await editor.load(noteID: created.id)
        return (editor, tagUseCase, created.id)
    }

    func testCreateAndAddTagUsesTheExactNameGiven() async throws {
        let (editor, tagUseCase, noteID) = try await makeEnvironment()

        await editor.createAndAddTag(name: "회의록")

        XCTAssertEqual(editor.noteTags.map(\.name), ["회의록"])
        let persisted = try await tagUseCase.tags(forNote: noteID)
        XCTAssertEqual(persisted.map(\.name), ["회의록"], "저장된 태그 이름이 실제로 입력한 이름과 정확히 일치해야 한다")
    }

    func testCreateAndAddTagNeverFallsBackToGenericNameWhenGivenARealName() async throws {
        let (editor, _, _) = try await makeEnvironment()

        await editor.createAndAddTag(name: "프로젝트 X")

        XCTAssertFalse(editor.noteTags.contains { $0.name == "새 태그" })
        XCTAssertEqual(editor.noteTags.first?.name, "프로젝트 X")
    }

    func testAddingExistingTagAssignsItToTheNote() async throws {
        let (editor, tagUseCase, noteID) = try await makeEnvironment()
        let tag = try await tagUseCase.createTag(name: "아이디어")

        await editor.addTag(tag)

        XCTAssertEqual(editor.noteTags.map(\.id), [tag.id])
        let persisted = try await tagUseCase.tags(forNote: noteID)
        XCTAssertEqual(persisted.map(\.id), [tag.id])
    }

    func testRemoveTagUnassignsAndPersists() async throws {
        let (editor, tagUseCase, noteID) = try await makeEnvironment()
        let tag = try await tagUseCase.createTag(name: "임시")
        await editor.addTag(tag)
        XCTAssertEqual(editor.noteTags.count, 1)

        await editor.removeTag(tag)

        XCTAssertTrue(editor.noteTags.isEmpty)
        let persisted = try await tagUseCase.tags(forNote: noteID)
        XCTAssertTrue(persisted.isEmpty)
    }

    // MARK: - onTagsChanged (사이드바 즉시 반영)

    func testCreateAndAddTagFiresOnTagsChanged() async throws {
        let (editor, _, _) = try await makeEnvironment()
        var firedCount = 0
        editor.onTagsChanged = { firedCount += 1 }

        await editor.createAndAddTag(name: "새 프로젝트")

        XCTAssertEqual(firedCount, 1, "사이드바가 새 태그를 바로 보여주려면 태그가 바뀔 때마다 콜백이 호출되어야 한다")
    }

    func testAddExistingTagFiresOnTagsChanged() async throws {
        let (editor, tagUseCase, _) = try await makeEnvironment()
        let tag = try await tagUseCase.createTag(name: "아이디어")
        var firedCount = 0
        editor.onTagsChanged = { firedCount += 1 }

        await editor.addTag(tag)

        XCTAssertEqual(firedCount, 1)
    }

    func testRemoveTagFiresOnTagsChanged() async throws {
        let (editor, tagUseCase, _) = try await makeEnvironment()
        let tag = try await tagUseCase.createTag(name: "임시")
        await editor.addTag(tag)
        var firedCount = 0
        editor.onTagsChanged = { firedCount += 1 }

        await editor.removeTag(tag)

        XCTAssertEqual(firedCount, 1)
    }

    func testAddingAlreadyAssignedTagDoesNotFireOnTagsChanged() async throws {
        let (editor, tagUseCase, _) = try await makeEnvironment()
        let tag = try await tagUseCase.createTag(name: "중복")
        await editor.addTag(tag)
        var firedCount = 0
        editor.onTagsChanged = { firedCount += 1 }

        await editor.addTag(tag) // 이미 붙어 있으니 아무 일도 없어야 한다

        XCTAssertEqual(firedCount, 0)
    }
}
