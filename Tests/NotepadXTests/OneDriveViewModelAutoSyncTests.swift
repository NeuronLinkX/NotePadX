import XCTest
@testable import NotepadX

/// `OneDriveViewModel.syncNoteIfConfigured`는 ContentView가 EditorViewModel.onNoteUpdated에
/// 연결해서, OneDrive 폴더를 한 번 설정해 두면 그 뒤로는 "지금 동기화"를 매번 누르지 않아도
/// 저장할 때마다 자동으로 반영되게 한다. 실제 업로드/다운로드/충돌 판정 로직 자체는
/// `OneDriveSyncUseCaseTests`가 이미 두텁게 검증하므로, 여기서는 이 자동 동기화 진입점이
/// "폴더 미설정 시 조용히 아무것도 하지 않는다"는 계약만 확인한다 — `FolderAccessService`의
/// folderURL은 NSOpenPanel/Keychain 북마크를 통해서만 설정되어 테스트에서 직접 주입할 수 없다.
@MainActor
final class OneDriveViewModelAutoSyncTests: XCTestCase {
    private var tempURL: URL!

    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotepadXOneDriveAutoSyncTests-\(UUID().uuidString).sqlite")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempURL)
    }

    func testDoesNothingAndDoesNotThrowWhenNoFolderIsConfigured() async throws {
        let db = try DatabaseManager(databaseURL: tempURL)
        try await SchemaMigrator.migrate(db)
        let index = SearchIndexService(db: db)
        let noteRepo = SQLiteNoteRepository(db: db)
        let noteUseCase = NoteUseCase(noteRepository: noteRepo, searchIndex: index)
        let syncUseCase = OneDriveSyncUseCase(
            noteRepository: noteRepo,
            syncStateRepository: SQLiteSyncStateRepository(db: db),
            searchIndex: index,
            deviceID: "test-device"
        )
        let viewModel = OneDriveViewModel(
            folderAccessService: FolderAccessService(keychain: KeychainService(service: "com.notepadx.tests.onedrive.\(UUID().uuidString)")),
            syncUseCase: syncUseCase,
            noteUseCase: noteUseCase
        )
        let note = try await noteUseCase.createNote(folderID: nil)

        XCTAssertNil(viewModel.folderURL)
        await viewModel.syncNoteIfConfigured(note.id)

        XCTAssertTrue(viewModel.conflicts.isEmpty)
        XCTAssertNil(viewModel.errorMessage, "폴더 미설정 상태에서는 오류창도 띄우지 않아야 한다 — 그냥 아무 일도 안 일어나는 게 맞다")
    }
}
