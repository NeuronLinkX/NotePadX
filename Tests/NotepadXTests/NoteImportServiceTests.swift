import XCTest
@testable import NotepadX

final class NoteImportServiceTests: XCTestCase {
    private var directory: URL!
    private var dbURL: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("NotepadXImport-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        dbURL = directory.appendingPathComponent("db.sqlite")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var folderRepository: SQLiteFolderRepository!

    private func makeUseCase() async throws -> (NoteUseCase, SearchIndexService) {
        let db = try DatabaseManager(databaseURL: dbURL)
        try await SchemaMigrator.migrate(db)
        let index = SearchIndexService(db: db)
        folderRepository = SQLiteFolderRepository(db: db)
        return (NoteUseCase(noteRepository: SQLiteNoteRepository(db: db), searchIndex: index), index)
    }

    private func write(_ name: String, _ data: Data) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    func testImportsMarkdownTextAndDocxAsNewSearchableNotes() async throws {
        let (useCase, index) = try await makeUseCase()
        let md = try write("회의록.md", Data("# 주간 회의\n\n- [ ] 일정 확정\n- [x] 자료 공유".utf8))
        let txt = try write("메모.txt", Data("첫 줄\n둘째 줄".utf8))
        var zip = ZipArchiveWriter()
        zip.addFile(path: "word/document.xml", data: Data(#"<w:document xmlns:w="w"><w:body><w:p><w:r><w:t>워드 본문 고유단어</w:t></w:r></w:p></w:body></w:document>"#.utf8))
        let docx = try write("보고서.docx", zip.finalize())

        let summary = await NoteImportService(noteUseCase: useCase).importFiles([md, txt, docx], folderID: nil)

        XCTAssertEqual(summary.importedIDs.count, 3)
        XCTAssertTrue(summary.failures.isEmpty, "\(summary.failures)")
        let notes = try await useCase.fetchNotes(filter: .all)
        XCTAssertEqual(Set(notes.map(\.title)), ["주간 회의", "메모", "보고서"])
        let hits = try await SearchUseCase(searchIndex: index).search(query: "고유단어", filters: SearchFilters())
        XCTAssertEqual(hits.count, 1, "가져온 Word 본문도 검색돼야 한다")
        let markdownNote = try XCTUnwrap(notes.first { $0.title == "주간 회의" })
        let document = try EditorDocument.decode(from: markdownNote.documentJSON)
        XCTAssertEqual(document.content.first?.type, "taskList")
    }

    func testImportNeverTouchesExistingNotesAndLandsInTheChosenFolder() async throws {
        let (useCase, _) = try await makeUseCase()
        let existing = try await useCase.createNote(folderID: nil)
        let saved = try useCase.applyEdit(to: existing, title: "기존 메모", document: EditorDocument.fromPlainText("그대로"), plainText: "그대로")
        try await useCase.save(saved)
        let folderID: UUID = try await {
            let folder = Folder(parentID: nil, name: "가져온 글")
            try await folderRepository.createFolder(folder)
            return folder.id
        }()
        let md = try write("새.md", Data("# 새 메모".utf8))

        let summary = await NoteImportService(noteUseCase: useCase).importFiles([md], folderID: folderID)

        XCTAssertEqual(summary.importedIDs.count, 1)
        let imported = try await useCase.fetchNote(id: XCTUnwrap(summary.importedIDs.first))
        XCTAssertEqual(imported?.folderID, folderID)
        let untouched = try await useCase.fetchNote(id: existing.id)
        XCTAssertEqual(untouched?.title, "기존 메모")
        XCTAssertEqual(untouched?.plainText, "그대로")
    }

    func testOneBadFileDoesNotStopTheOthers() async throws {
        let (useCase, _) = try await makeUseCase()
        let good = try write("좋음.md", Data("# 좋은 파일".utf8))
        let badDocx = try write("깨짐.docx", Data("이건 zip이 아님".utf8))
        let unsupported = try write("그림.png", Data([1, 2, 3]))

        let summary = await NoteImportService(noteUseCase: useCase).importFiles([badDocx, good, unsupported], folderID: nil)

        XCTAssertEqual(summary.importedIDs.count, 1)
        XCTAssertEqual(summary.failures.map(\.name), ["깨짐.docx", "그림.png"])
        XCTAssertTrue(summary.message.contains("가져오지 못한 항목"))
        let count = try await useCase.fetchNotes(filter: .all).count
        XCTAssertEqual(count, 1, "실패한 파일은 빈 메모조차 남기지 않는다")
    }

    func testOversizedTextFileIsRejected() throws {
        let huge = try write("거대.txt", Data(count: NoteImportService.maxTextBytes + 1))
        XCTAssertThrowsError(try NoteImportService.load(huge)) {
            guard case NoteImportService.ImportError.tooLarge = $0 else { return XCTFail("\($0)") }
        }
    }

    func testTextEncodings() throws {
        XCTAssertEqual(try NoteImportService.decodeText(Data([0xEF, 0xBB, 0xBF]) + Data("BOM 글".utf8)), "BOM 글")
        XCTAssertEqual(try NoteImportService.decodeText("UTF-16 글".data(using: .utf16)!), "UTF-16 글")
        let eucKR = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.EUC_KR.rawValue)))
        let legacy = try XCTUnwrap("안녕하세요 한글 메모".data(using: eucKR))
        XCTAssertEqual(try NoteImportService.decodeText(legacy), "안녕하세요 한글 메모")
    }

    func testAppleNotesImportUsesFetcherAndReportsPermissionProblems() async throws {
        struct Fake: AppleNotesFetching {
            var result: Result<[AppleNoteRaw], Error>
            func fetchNotes() async throws -> [AppleNoteRaw] { try result.get() }
        }
        let (useCase, _) = try await makeUseCase()
        let service = NoteImportService(noteUseCase: useCase)

        let ok = await service.importAppleNotes(
            fetcher: Fake(result: .success([
                AppleNoteRaw(title: "장보기", html: "<div><h1>장보기</h1></div><div>우유</div>"),
                AppleNoteRaw(title: "", html: "<div>제목 없는 메모</div>"),
            ])),
            folderID: nil
        )
        XCTAssertEqual(ok.importedIDs.count, 2)
        let titles = try await useCase.fetchNotes(filter: .all).map(\.title)
        XCTAssertTrue(titles.contains("장보기"))
        XCTAssertTrue(titles.contains("Apple 메모 2"))

        let denied = await service.importAppleNotes(fetcher: Fake(result: .failure(AppleNotesError.notAuthorized)), folderID: nil)
        XCTAssertTrue(denied.importedIDs.isEmpty)
        XCTAssertTrue(denied.message.contains("자동화"))

        let empty = await service.importAppleNotes(fetcher: Fake(result: .success([])), folderID: nil)
        XCTAssertEqual(empty.failures.count, 1)
    }

    func testAppleScriptResultParsing() {
        let outer = NSAppleEventDescriptor.list()
        for (title, html) in [("A", "<div>a</div>"), ("B", "<div>b</div>")] {
            let item = NSAppleEventDescriptor.list()
            item.insert(NSAppleEventDescriptor(string: title), at: 1)
            item.insert(NSAppleEventDescriptor(string: html), at: 2)
            outer.insert(item, at: outer.numberOfItems + 1)
        }
        XCTAssertEqual(SystemAppleNotesFetcher.parse(outer), [AppleNoteRaw(title: "A", html: "<div>a</div>"), AppleNoteRaw(title: "B", html: "<div>b</div>")])
        XCTAssertTrue(SystemAppleNotesFetcher.parse(NSAppleEventDescriptor.list()).isEmpty)
    }
}
