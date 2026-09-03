import XCTest
@testable import NotepadX

final class AttachmentStorageTests: XCTestCase {
    private var tempDirectory: URL!
    private var storage: AttachmentStorage!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotepadXAttachmentTests-\(UUID().uuidString)")
        let directory = tempDirectory!
        storage = AttachmentStorage(baseDirectoryProvider: { directory })
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func testSaveWritesFileNamedAfterOriginalInsideAnIdFolder() throws {
        let data = Data("hello".utf8)
        let fileURL = try storage.save(attachmentId: "abc-123", fileName: "보고서.pdf", base64Data: data.base64EncodedString())

        XCTAssertEqual(fileURL.lastPathComponent, "보고서.pdf")
        XCTAssertEqual(fileURL.deletingLastPathComponent().lastPathComponent, "abc-123")
        XCTAssertEqual(try Data(contentsOf: fileURL), data)
    }

    func testUrlResolvesToTheSavedFile() throws {
        let data = Data("world".utf8)
        _ = try storage.save(attachmentId: "id-1", fileName: "note.txt", base64Data: data.base64EncodedString())

        let resolved = try storage.url(attachmentId: "id-1", fileName: "note.txt")
        XCTAssertEqual(try Data(contentsOf: resolved), data)
    }

    func testUrlThrowsWhenAttachmentWasNeverSaved() {
        XCTAssertThrowsError(try storage.url(attachmentId: "missing", fileName: "ghost.txt")) { error in
            XCTAssertTrue(error is AttachmentStorageError)
        }
    }

    func testSaveThrowsOnInvalidBase64() {
        XCTAssertThrowsError(try storage.save(attachmentId: "bad", fileName: "x.txt", base64Data: "not-valid-base64!!"))
    }

    /// 같은 파일명을 다른 첨부로 두 번 저장해도(id가 다르면) 서로 덮어쓰지 않아야 한다 —
    /// id별 폴더로 나누는 이유가 바로 이거다.
    func testTwoAttachmentsWithSameFileNameDoNotCollide() throws {
        let first = try storage.save(attachmentId: "id-a", fileName: "동일이름.txt", base64Data: Data("A".utf8).base64EncodedString())
        let second = try storage.save(attachmentId: "id-b", fileName: "동일이름.txt", base64Data: Data("B".utf8).base64EncodedString())

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try Data(contentsOf: first), Data("A".utf8))
        XCTAssertEqual(try Data(contentsOf: second), Data("B".utf8))
    }

    /// attachmentId가 경로 구분자를 담고 있어도(신뢰할 수 없는 입력) 상위 폴더로 빠져나가면 안 된다.
    func testAttachmentIdWithPathSeparatorsIsSanitized() throws {
        let fileURL = try storage.save(attachmentId: "../../evil", fileName: "x.txt", base64Data: Data("x".utf8).base64EncodedString())
        XCTAssertTrue(fileURL.path.hasPrefix(tempDirectory.path), "정제되지 않은 attachmentId로 저장 위치가 base 디렉터리 밖으로 나갔다: \(fileURL.path)")
    }
}
