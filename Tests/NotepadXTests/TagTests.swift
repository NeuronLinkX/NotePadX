import XCTest
@testable import NotepadX

final class TagTests: XCTestCase {
    private var tempURL: URL!

    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotepadXTagTests-\(UUID().uuidString).sqlite")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempURL)
    }

    private func makeStack() async throws -> (notes: NoteUseCase, tags: TagUseCase) {
        let db = try DatabaseManager(databaseURL: tempURL)
        try await SchemaMigrator.migrate(db)
        let index = SearchIndexService(db: db)
        let noteRepo = SQLiteNoteRepository(db: db)
        let tagRepo = SQLiteTagRepository(db: db)
        return (
            NoteUseCase(noteRepository: noteRepo, searchIndex: index),
            TagUseCase(tagRepository: tagRepo, searchIndex: index)
        )
    }

    func testCreateAssignAndListTagsForNote() async throws {
        let stack = try await makeStack()
        let tagA = try await stack.tags.createTag(name: "중요")
        let tagB = try await stack.tags.createTag(name: "회고")
        let note = try await stack.notes.createNote(folderID: nil)

        try await stack.tags.setTags(noteID: note.id, tagIDs: [tagA.id, tagB.id])
        let tags = try await stack.tags.tags(forNote: note.id)

        XCTAssertEqual(Set(tags.map(\.id)), Set([tagA.id, tagB.id]))
    }

    func testSetTagsReplacesPreviousSet() async throws {
        let stack = try await makeStack()
        let tagA = try await stack.tags.createTag(name: "A")
        let tagB = try await stack.tags.createTag(name: "B")
        let note = try await stack.notes.createNote(folderID: nil)

        try await stack.tags.setTags(noteID: note.id, tagIDs: [tagA.id])
        try await stack.tags.setTags(noteID: note.id, tagIDs: [tagB.id])

        let tags = try await stack.tags.tags(forNote: note.id)
        XCTAssertEqual(tags.map(\.id), [tagB.id])
    }

    func testFindOrCreateTagReusesExistingByName() async throws {
        let stack = try await makeStack()
        let first = try await stack.tags.findOrCreateTag(name: "재사용")
        let second = try await stack.tags.findOrCreateTag(name: "재사용")
        XCTAssertEqual(first.id, second.id)

        let all = try await stack.tags.fetchAllTags()
        XCTAssertEqual(all.filter { $0.name == "재사용" }.count, 1)
    }

    func testDeletingTagRemovesItFromNotes() async throws {
        let stack = try await makeStack()
        let tag = try await stack.tags.createTag(name: "임시태그")
        let note = try await stack.notes.createNote(folderID: nil)
        try await stack.tags.setTags(noteID: note.id, tagIDs: [tag.id])

        try await stack.tags.delete(id: tag.id)

        let tags = try await stack.tags.tags(forNote: note.id)
        XCTAssertTrue(tags.isEmpty)
    }

    func testNoteCountForTag() async throws {
        let stack = try await makeStack()
        let tag = try await stack.tags.createTag(name: "카운트")
        let noteA = try await stack.notes.createNote(folderID: nil)
        let noteB = try await stack.notes.createNote(folderID: nil)
        try await stack.tags.setTags(noteID: noteA.id, tagIDs: [tag.id])
        try await stack.tags.setTags(noteID: noteB.id, tagIDs: [tag.id])

        let count = try await stack.tags.noteCount(tagID: tag.id)
        XCTAssertEqual(count, 2)
    }
}
