import XCTest
@testable import NotepadX

/// NSOpenPanel 없이 임의의 임시 폴더를 rootURL로 바로 넘겨 실제 파일시스템에
/// document.json/metadata.json 패키지를 쓰고 읽는지 검증한다.
final class OneDriveFolderSyncProviderTests: XCTestCase {
    private var rootURL: URL!

    override func setUpWithError() throws {
        rootURL = FileManager.default.temporaryDirectory.appendingPathComponent("NotepadXOneDriveFolder-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: rootURL)
    }

    private func sampleDocument(noteID: UUID = UUID(), text: String = "안녕하세요") -> SyncDocument {
        let document = EditorDocument.fromPlainText(text)
        return SyncDocument(
            noteID: noteID,
            title: "테스트 노트",
            documentJSON: (try? document.encoded()) ?? Data(),
            plainText: text,
            updatedAt: Date(),
            contentHash: NoteUseCase.contentHash(for: text),
            baseRevision: nil,
            deviceID: "device-a"
        )
    }

    func testUploadWritesExpectedPackageStructure() async throws {
        let provider = OneDriveFolderSyncProvider(rootURL: rootURL, deviceID: "device-a")
        let document = sampleDocument()
        try await provider.upload(document)

        let packageURL = rootURL.appendingPathComponent("\(document.noteID.uuidString).notepadx")
        XCTAssertTrue(FileManager.default.fileExists(atPath: packageURL.appendingPathComponent("document.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: packageURL.appendingPathComponent("metadata.json").path))
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: packageURL.appendingPathComponent("attachments").path, isDirectory: &isDirectory)
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testUploadThenDownloadRoundTrips() async throws {
        let provider = OneDriveFolderSyncProvider(rootURL: rootURL, deviceID: "device-a")
        let document = sampleDocument(text: "왕복 테스트 내용")
        try await provider.upload(document)

        let downloaded = try await provider.download(id: document.noteID.uuidString)
        XCTAssertEqual(downloaded.plainText, "왕복 테스트 내용")
        XCTAssertEqual(downloaded.title, document.title)
        XCTAssertEqual(downloaded.contentHash, document.contentHash)
    }

    func testDownloadingMissingNoteThrowsNotFound() async throws {
        let provider = OneDriveFolderSyncProvider(rootURL: rootURL, deviceID: "device-a")
        do {
            _ = try await provider.download(id: UUID().uuidString)
            XCTFail("없는 노트를 다운로드하면 실패해야 한다")
        } catch SyncProviderError.notFound {
            // 기대한 대로
        }
    }

    func testListNotesReturnsUploadedNotes() async throws {
        let provider = OneDriveFolderSyncProvider(rootURL: rootURL, deviceID: "device-a")
        let first = sampleDocument()
        let second = sampleDocument()
        try await provider.upload(first)
        try await provider.upload(second)

        let listed = try await provider.listNotes()
        XCTAssertEqual(Set(listed.map(\.id)), Set([first.noteID.uuidString, second.noteID.uuidString]))
    }

    func testDeleteRemovesPackage() async throws {
        let provider = OneDriveFolderSyncProvider(rootURL: rootURL, deviceID: "device-a")
        let document = sampleDocument()
        try await provider.upload(document)
        try await provider.delete(id: document.noteID.uuidString)

        do {
            _ = try await provider.download(id: document.noteID.uuidString)
            XCTFail("삭제된 노트는 다운로드에 실패해야 한다")
        } catch SyncProviderError.notFound {
            // 기대한 대로
        }
    }
}
