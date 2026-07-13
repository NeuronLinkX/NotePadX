import XCTest
@testable import NotepadX

final class SearchIndexServiceTests: XCTestCase {
    private var tempURL: URL!

    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotepadXSearchTests-\(UUID().uuidString).sqlite")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempURL)
    }

    private func makeStack() async throws -> (db: DatabaseManager, notes: NoteUseCase, folders: FolderUseCase, tags: TagUseCase, search: SearchUseCase) {
        let db = try DatabaseManager(databaseURL: tempURL)
        try await SchemaMigrator.migrate(db)
        let index = SearchIndexService(db: db)
        let noteRepo = SQLiteNoteRepository(db: db)
        let folderRepo = SQLiteFolderRepository(db: db)
        let tagRepo = SQLiteTagRepository(db: db)
        return (
            db,
            NoteUseCase(noteRepository: noteRepo, searchIndex: index),
            FolderUseCase(folderRepository: folderRepo, noteRepository: noteRepo, searchIndex: index),
            TagUseCase(tagRepository: tagRepo, searchIndex: index),
            SearchUseCase(searchIndex: index)
        )
    }

    func testKoreanSubstringSearch() async throws {
        let stack = try await makeStack()
        let note = try await stack.notes.createNote(folderID: nil)
        let edited = try stack.notes.applyEdit(
            to: note,
            title: "회의록",
            document: .fromPlainText("오늘 회의에서 반갑습니다 라고 인사했다"),
            plainText: "오늘 회의에서 반갑습니다 라고 인사했다"
        )
        try await stack.notes.save(edited)

        let hits = try await stack.search.search(query: "반갑습니다")
        XCTAssertTrue(hits.contains { $0.noteID == note.id })
    }

    func testEnglishAndCodeIdentifierSearch() async throws {
        let stack = try await makeStack()
        let note = try await stack.notes.createNote(folderID: nil)
        let code = "void computeChecksum(int value) { return value; }"
        let edited = try stack.notes.applyEdit(to: note, title: "Snippet", document: .fromPlainText(code), plainText: code)
        try await stack.notes.save(edited)

        let hits = try await stack.search.search(query: "computeChecksum")
        XCTAssertTrue(hits.contains { $0.noteID == note.id })
    }

    func testShortQueryFallsBackToLike() async throws {
        let stack = try await makeStack()
        let note = try await stack.notes.createNote(folderID: nil)
        let edited = try stack.notes.applyEdit(to: note, title: "AB", document: .fromPlainText("AB 짧은 질의"), plainText: "AB 짧은 질의")
        try await stack.notes.save(edited)

        // trigram은 3글자 미만은 매칭 못 하므로 LIKE 폴백 경로를 태운다.
        let hits = try await stack.search.search(query: "AB")
        XCTAssertTrue(hits.contains { $0.noteID == note.id })
    }

    func testTrashedNoteIsExcludedFromSearch() async throws {
        let stack = try await makeStack()
        let note = try await stack.notes.createNote(folderID: nil)
        let edited = try stack.notes.applyEdit(to: note, title: "임시", document: .fromPlainText("찾을수없는문자열123"), plainText: "찾을수없는문자열123")
        try await stack.notes.save(edited)
        try await stack.notes.moveToTrash(id: note.id)

        let hits = try await stack.search.search(query: "찾을수없는문자열123")
        XCTAssertFalse(hits.contains { $0.noteID == note.id })
    }

    func testTagFilterNarrowsResults() async throws {
        let stack = try await makeStack()
        let matchingTag = try await stack.tags.createTag(name: "업무")
        let otherTag = try await stack.tags.createTag(name: "개인")

        let noteA = try await stack.notes.createNote(folderID: nil)
        let editedA = try stack.notes.applyEdit(to: noteA, title: "A", document: .fromPlainText("공통키워드 alpha"), plainText: "공통키워드 alpha")
        try await stack.notes.save(editedA)
        try await stack.tags.setTags(noteID: noteA.id, tagIDs: [matchingTag.id])

        let noteB = try await stack.notes.createNote(folderID: nil)
        let editedB = try stack.notes.applyEdit(to: noteB, title: "B", document: .fromPlainText("공통키워드 beta"), plainText: "공통키워드 beta")
        try await stack.notes.save(editedB)
        try await stack.tags.setTags(noteID: noteB.id, tagIDs: [otherTag.id])

        var filters = SearchFilters()
        filters.tagID = matchingTag.id
        let hits = try await stack.search.search(query: "공통키워드", filters: filters)

        XCTAssertTrue(hits.contains { $0.noteID == noteA.id })
        XCTAssertFalse(hits.contains { $0.noteID == noteB.id })
    }

    func testFolderRenameResyncsSearchIndex() async throws {
        let stack = try await makeStack()
        let folder = try await stack.folders.createFolder(name: "원래이름폴더", parentID: nil)
        let note = try await stack.notes.createNote(folderID: folder.id)
        let edited = try stack.notes.applyEdit(to: note, title: "메모", document: .fromPlainText("본문"), plainText: "본문")
        try await stack.notes.save(edited)

        try await stack.folders.rename(id: folder.id, to: "새폴더이름")

        let hits = try await stack.search.search(query: "새폴더이름")
        XCTAssertTrue(hits.contains { $0.noteID == note.id })
    }
}
