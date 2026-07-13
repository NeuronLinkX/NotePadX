import XCTest
@testable import NotepadX

final class OneDriveSyncUseCaseTests: XCTestCase {
    private var tempURL: URL!

    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotepadXOneDriveTests-\(UUID().uuidString).sqlite")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempURL)
    }

    private func makeStack() async throws -> (notes: NoteUseCase, noteRepo: SQLiteNoteRepository, sync: OneDriveSyncUseCase) {
        let db = try DatabaseManager(databaseURL: tempURL)
        try await SchemaMigrator.migrate(db)
        let index = SearchIndexService(db: db)
        let noteRepo = SQLiteNoteRepository(db: db)
        let syncStateRepo = SQLiteSyncStateRepository(db: db)
        return (
            NoteUseCase(noteRepository: noteRepo, searchIndex: index),
            noteRepo,
            OneDriveSyncUseCase(noteRepository: noteRepo, syncStateRepository: syncStateRepo, searchIndex: index, deviceID: "test-device")
        )
    }

    func testFirstSyncUploadsWhenRemoteIsAbsent() async throws {
        let stack = try await makeStack()
        let note = try await stack.notes.createNote(folderID: nil)
        let provider = FakeCloudSyncProvider()

        let outcome = try await stack.sync.sync(noteID: note.id, using: provider)

        guard case .uploaded = outcome else { return XCTFail("첫 동기화는 업로드여야 한다: \(outcome)") }
        let remoteNotes = try await provider.listNotes()
        XCTAssertTrue(remoteNotes.contains { $0.id == note.id.uuidString })
    }

    func testUpToDateWhenNeitherSideChanged() async throws {
        let stack = try await makeStack()
        let note = try await stack.notes.createNote(folderID: nil)
        let provider = FakeCloudSyncProvider()
        _ = try await stack.sync.sync(noteID: note.id, using: provider) // 초기 업로드

        let outcome = try await stack.sync.sync(noteID: note.id, using: provider)
        guard case .upToDate = outcome else { return XCTFail("변경이 없으면 upToDate여야 한다: \(outcome)") }
    }

    func testLocalOnlyChangeUploads() async throws {
        let stack = try await makeStack()
        let note = try await stack.notes.createNote(folderID: nil)
        let provider = FakeCloudSyncProvider()
        _ = try await stack.sync.sync(noteID: note.id, using: provider)

        let edited = try stack.notes.applyEdit(to: note, title: "로컬 수정", document: .fromPlainText("로컬 변경 내용"), plainText: "로컬 변경 내용")
        try await stack.notes.save(edited)

        let outcome = try await stack.sync.sync(noteID: note.id, using: provider)
        guard case .uploaded = outcome else { return XCTFail("로컬만 바뀌면 업로드여야 한다: \(outcome)") }

        let remote = try await provider.download(id: note.id.uuidString)
        XCTAssertEqual(remote.plainText, "로컬 변경 내용")
    }

    func testRemoteOnlyChangeDownloads() async throws {
        let stack = try await makeStack()
        let note = try await stack.notes.createNote(folderID: nil)
        let provider = FakeCloudSyncProvider()
        _ = try await stack.sync.sync(noteID: note.id, using: provider)

        var remoteVersion = try await provider.download(id: note.id.uuidString)
        remoteVersion.title = "원격 수정"
        remoteVersion.plainText = "원격 변경 내용"
        remoteVersion.documentJSON = try EditorDocument.fromPlainText("원격 변경 내용").encoded()
        remoteVersion.contentHash = NoteUseCase.contentHash(for: "원격 변경 내용")
        remoteVersion.updatedAt = Date().addingTimeInterval(10)
        try await provider.upload(remoteVersion)

        let outcome = try await stack.sync.sync(noteID: note.id, using: provider)
        guard case .downloaded = outcome else { return XCTFail("원격만 바뀌면 다운로드여야 한다: \(outcome)") }

        let updatedLocal = try await stack.noteRepo.fetchNote(id: note.id)
        XCTAssertEqual(updatedLocal?.plainText, "원격 변경 내용")
    }

    func testBothChangedWithDifferentContentIsAConflict() async throws {
        let stack = try await makeStack()
        let note = try await stack.notes.createNote(folderID: nil)
        let provider = FakeCloudSyncProvider()
        _ = try await stack.sync.sync(noteID: note.id, using: provider)

        let editedLocal = try stack.notes.applyEdit(to: note, title: "로컬", document: .fromPlainText("로컬 내용"), plainText: "로컬 내용")
        try await stack.notes.save(editedLocal)

        var remoteVersion = try await provider.download(id: note.id.uuidString)
        remoteVersion.title = "원격"
        remoteVersion.plainText = "원격 내용"
        remoteVersion.contentHash = NoteUseCase.contentHash(for: "원격 내용")
        remoteVersion.updatedAt = Date().addingTimeInterval(10)
        try await provider.upload(remoteVersion)

        let outcome = try await stack.sync.sync(noteID: note.id, using: provider)
        guard case .conflict(let conflict) = outcome else { return XCTFail("둘 다 바뀌면 충돌이어야 한다: \(outcome)") }
        XCTAssertEqual(conflict.localPlainText, "로컬 내용")
        XCTAssertEqual(conflict.remotePlainText, "원격 내용")
    }

    func testBothChangedButSameResultIsNotAConflict() async throws {
        let stack = try await makeStack()
        let note = try await stack.notes.createNote(folderID: nil)
        let provider = FakeCloudSyncProvider()
        _ = try await stack.sync.sync(noteID: note.id, using: provider)

        let editedLocal = try stack.notes.applyEdit(to: note, title: "같음", document: .fromPlainText("같은 내용"), plainText: "같은 내용")
        try await stack.notes.save(editedLocal)

        var remoteVersion = try await provider.download(id: note.id.uuidString)
        remoteVersion.plainText = "같은 내용"
        remoteVersion.contentHash = NoteUseCase.contentHash(for: "같은 내용")
        remoteVersion.updatedAt = Date().addingTimeInterval(10)
        try await provider.upload(remoteVersion)

        let outcome = try await stack.sync.sync(noteID: note.id, using: provider)
        guard case .upToDate = outcome else { return XCTFail("내용이 같으면 충돌이 아니어야 한다: \(outcome)") }
    }

    func testResolveConflictKeepLocalOverwritesRemote() async throws {
        let stack = try await makeStack()
        let note = try await stack.notes.createNote(folderID: nil)
        let provider = FakeCloudSyncProvider()
        _ = try await stack.sync.sync(noteID: note.id, using: provider)

        let editedLocal = try stack.notes.applyEdit(to: note, title: "로컬", document: .fromPlainText("로컬 승리"), plainText: "로컬 승리")
        try await stack.notes.save(editedLocal)
        var remoteVersion = try await provider.download(id: note.id.uuidString)
        remoteVersion.plainText = "원격 내용"
        remoteVersion.contentHash = NoteUseCase.contentHash(for: "원격 내용")
        remoteVersion.updatedAt = Date().addingTimeInterval(10)
        try await provider.upload(remoteVersion)

        guard case .conflict(let conflict) = try await stack.sync.sync(noteID: note.id, using: provider) else {
            return XCTFail("충돌이 먼저 감지돼야 한다")
        }
        try await stack.sync.resolveConflict(conflict, resolution: .keepLocal, using: provider)

        let remoteAfter = try await provider.download(id: note.id.uuidString)
        XCTAssertEqual(remoteAfter.plainText, "로컬 승리")
    }

    func testResolveConflictKeepBothCreatesDuplicateNote() async throws {
        let stack = try await makeStack()
        let note = try await stack.notes.createNote(folderID: nil)
        let provider = FakeCloudSyncProvider()
        _ = try await stack.sync.sync(noteID: note.id, using: provider)

        let editedLocal = try stack.notes.applyEdit(to: note, title: "로컬", document: .fromPlainText("로컬 내용"), plainText: "로컬 내용")
        try await stack.notes.save(editedLocal)
        var remoteVersion = try await provider.download(id: note.id.uuidString)
        remoteVersion.title = "원격 제목"
        remoteVersion.plainText = "원격 내용"
        remoteVersion.contentHash = NoteUseCase.contentHash(for: "원격 내용")
        remoteVersion.updatedAt = Date().addingTimeInterval(10)
        try await provider.upload(remoteVersion)

        guard case .conflict(let conflict) = try await stack.sync.sync(noteID: note.id, using: provider) else {
            return XCTFail("충돌이 먼저 감지돼야 한다")
        }
        try await stack.sync.resolveConflict(conflict, resolution: .keepBoth, using: provider)

        let allNotes = try await stack.noteRepo.fetchNotes(filter: .all, sortOrder: .updatedDescending)
        XCTAssertEqual(allNotes.count, 2, "원본 + 원격을 복제한 새 노트로 총 2개가 있어야 한다")
        XCTAssertTrue(allNotes.contains { $0.plainText == "로컬 내용" })
        XCTAssertTrue(allNotes.contains { $0.plainText == "원격 내용" })
    }
}
