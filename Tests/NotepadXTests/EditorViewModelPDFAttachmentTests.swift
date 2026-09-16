import XCTest
@testable import NotepadX

/// PDF 첨부파일을 클릭하면 기본 앱으로 넘기는 대신 인앱 미리보기(pdfPreviewURL)로
/// 라우팅되는지 검증한다 (스펙: Office Viewer — PDF). 다른 파일 형식까지 여기서
/// 같이 검증하면 실제로 NSWorkspace.shared.open이 호출되어 테스트 중 외부 앱이 열려
/// 버리므로, 이 테스트는 PDF 케이스만 다룬다.
@MainActor
final class EditorViewModelPDFAttachmentTests: XCTestCase {
    private var dbURL: URL!
    private var attachmentsDir: URL!

    override func setUpWithError() throws {
        let unique = UUID().uuidString
        dbURL = FileManager.default.temporaryDirectory.appendingPathComponent("NotepadXPDFAttachmentTests-\(unique).sqlite")
        attachmentsDir = FileManager.default.temporaryDirectory.appendingPathComponent("NotepadXPDFAttachmentTests-\(unique)-attachments")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dbURL)
        try? FileManager.default.removeItem(at: attachmentsDir)
    }

    func testClickingAPDFAttachmentSetsPdfPreviewURLInsteadOfOpeningExternally() async throws {
        let db = try DatabaseManager(databaseURL: dbURL)
        try await SchemaMigrator.migrate(db)
        let index = SearchIndexService(db: db)
        let noteUseCase = NoteUseCase(noteRepository: SQLiteNoteRepository(db: db), searchIndex: index)
        let tagUseCase = TagUseCase(tagRepository: SQLiteTagRepository(db: db), searchIndex: index)
        let revisionUseCase = NoteRevisionUseCase(
            revisionRepository: SQLiteNoteRevisionRepository(db: db),
            noteRepository: SQLiteNoteRepository(db: db)
        )
        let attachmentsDirCopy = attachmentsDir!
        let attachmentStorage = AttachmentStorage(baseDirectoryProvider: { attachmentsDirCopy })
        let placeholderPDFBytes = Data("%PDF-1.4 placeholder".utf8)
        let attachmentId = UUID().uuidString
        _ = try attachmentStorage.save(attachmentId: attachmentId, fileName: "보고서.pdf", base64Data: placeholderPDFBytes.base64EncodedString())

        let note = try await noteUseCase.createNote(folderID: nil)
        let editor = EditorViewModel(
            noteUseCase: noteUseCase,
            tagUseCase: tagUseCase,
            revisionUseCase: revisionUseCase,
            attachmentStorage: attachmentStorage
        )
        await editor.load(noteID: note.id)

        XCTAssertNil(editor.pdfPreviewURL)
        editor.editorBridge(editor.richEditor.bridge, didRequestOpenAttachment: OpenAttachmentPayload(attachmentId: attachmentId, fileName: "보고서.pdf"))

        XCTAssertEqual(editor.pdfPreviewURL?.lastPathComponent, "보고서.pdf")
    }

    func testLoadingADifferentNoteClearsAnyOpenPDFPreview() async throws {
        let db = try DatabaseManager(databaseURL: dbURL)
        try await SchemaMigrator.migrate(db)
        let index = SearchIndexService(db: db)
        let noteUseCase = NoteUseCase(noteRepository: SQLiteNoteRepository(db: db), searchIndex: index)
        let tagUseCase = TagUseCase(tagRepository: SQLiteTagRepository(db: db), searchIndex: index)
        let revisionUseCase = NoteRevisionUseCase(
            revisionRepository: SQLiteNoteRevisionRepository(db: db),
            noteRepository: SQLiteNoteRepository(db: db)
        )
        let attachmentsDirCopy = attachmentsDir!
        let attachmentStorage = AttachmentStorage(baseDirectoryProvider: { attachmentsDirCopy })
        let attachmentId = UUID().uuidString
        _ = try attachmentStorage.save(attachmentId: attachmentId, fileName: "a.pdf", base64Data: Data("%PDF-1.4".utf8).base64EncodedString())

        let noteA = try await noteUseCase.createNote(folderID: nil)
        let noteB = try await noteUseCase.createNote(folderID: nil)
        let editor = EditorViewModel(
            noteUseCase: noteUseCase,
            tagUseCase: tagUseCase,
            revisionUseCase: revisionUseCase,
            attachmentStorage: attachmentStorage
        )
        await editor.load(noteID: noteA.id)
        editor.editorBridge(editor.richEditor.bridge, didRequestOpenAttachment: OpenAttachmentPayload(attachmentId: attachmentId, fileName: "a.pdf"))
        XCTAssertNotNil(editor.pdfPreviewURL)

        await editor.load(noteID: noteB.id)
        XCTAssertNil(editor.pdfPreviewURL, "다른 노트로 전환하면 이전 노트의 PDF 미리보기가 남아 있으면 안 된다")
    }
}
