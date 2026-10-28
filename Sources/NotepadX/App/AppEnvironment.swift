import Foundation

/// 앱 전역 의존성 컨테이너. 뷰는 데이터베이스나 파일시스템을 직접 다루지 않고
/// 이 컨테이너가 제공하는 UseCase를 통해서만 접근한다.
@MainActor
final class AppEnvironment: ObservableObject {
    let noteUseCase: NoteUseCase
    let folderUseCase: FolderUseCase
    let tagUseCase: TagUseCase
    let searchUseCase: SearchUseCase
    let revisionUseCase: NoteRevisionUseCase
    let oneDriveViewModel: OneDriveViewModel
    private let database: DatabaseManager
    /// 시작 후 백그라운드 점검(`PRAGMA quick_check`)에서 문제가 발견되면 그 내용. 화면이 알려 준다.
    @Published var integrityProblem: String?

    private init(
        database: DatabaseManager,
        noteUseCase: NoteUseCase,
        folderUseCase: FolderUseCase,
        tagUseCase: TagUseCase,
        searchUseCase: SearchUseCase,
        revisionUseCase: NoteRevisionUseCase,
        oneDriveViewModel: OneDriveViewModel
    ) {
        self.database = database
        self.noteUseCase = noteUseCase
        self.folderUseCase = folderUseCase
        self.tagUseCase = tagUseCase
        self.searchUseCase = searchUseCase
        self.revisionUseCase = revisionUseCase
        self.oneDriveViewModel = oneDriveViewModel
    }

    /// 데이터베이스를 Application Support 하위에 열고 마이그레이션을 적용한 뒤
    /// 의존성 그래프를 구성한다. 실패 시 호출자가 사용자에게 오류를 보여줘야 한다.
    static func bootstrap() async throws -> AppEnvironment {
        let databaseURL = try AppConfig.databaseURL()
        let backups = BackupCoordinator.shared.service

        // 설정에서 복원이 예약돼 있으면 DB를 열기 전에 파일을 교체한다(복원 전 데이터는 이미 백업돼 있다).
        backups.applyStagedRestore(databaseURL: databaseURL)

        let database = try DatabaseManager(databaseURL: databaseURL)

        // 스키마(데이터 구조)를 바꾸기 전에는 항상 스냅샷을 남긴다. 그게 안 되면 안전망 없이
        // 기존 데이터를 건드리지 않도록 업데이트 자체를 멈춘다.
        let pending = try await SchemaMigrator.pendingState(database)
        let tookSafetySnapshot = pending.hasExistingData && pending.pendingCount > 0
        if tookSafetySnapshot {
            do {
                try await backups.createBackup(from: database, kind: .preMigration)
            } catch {
                throw AppError.databaseFailure("업데이트 전 안전 백업에 실패해 데이터 업데이트를 중단했습니다 — \(error.localizedDescription)")
            }
        }
        try await SchemaMigrator.migrate(database)
        await BackupCoordinator.shared.configure(database: database)

        let noteRepository = SQLiteNoteRepository(db: database)
        let folderRepository = SQLiteFolderRepository(db: database)
        let tagRepository = SQLiteTagRepository(db: database)
        let revisionRepository = SQLiteNoteRevisionRepository(db: database)
        let syncStateRepository = SQLiteSyncStateRepository(db: database)
        let searchIndex = SearchIndexService(db: database)
        let noteUseCase = NoteUseCase(noteRepository: noteRepository, searchIndex: searchIndex)

        let folderAccessService = FolderAccessService()
        // 기다리지 않는다 — Keychain 접근 허용 창이 떠 있어도 앱 화면은 바로 보여야 한다.
        Task { await folderAccessService.restoreAccessIfAvailable() }
        let oneDriveSyncUseCase = OneDriveSyncUseCase(
            noteRepository: noteRepository,
            syncStateRepository: syncStateRepository,
            searchIndex: searchIndex,
            deviceID: AppConfig.deviceID
        )
        let oneDriveViewModel = OneDriveViewModel(
            folderAccessService: folderAccessService,
            syncUseCase: oneDriveSyncUseCase,
            noteUseCase: noteUseCase
        )

        let environment = AppEnvironment(
            database: database,
            noteUseCase: noteUseCase,
            folderUseCase: FolderUseCase(folderRepository: folderRepository, noteRepository: noteRepository, searchIndex: searchIndex),
            tagUseCase: TagUseCase(tagRepository: tagRepository, searchIndex: searchIndex),
            searchUseCase: SearchUseCase(searchIndex: searchIndex),
            revisionUseCase: NoteRevisionUseCase(revisionRepository: revisionRepository, noteRepository: noteRepository),
            oneDriveViewModel: oneDriveViewModel
        )

        Task { try? await environment.noteUseCase.purgeExpiredTrash() }
        QuickCaptureController.shared.configure(noteUseCase: environment.noteUseCase)

        await WidgetSnapshotService.shared.configure(database: database)
        await SpotlightIndexService.shared.configure(database: database)
        Task { await ExternalSurfaces.refresh() }

        // 데이터 점검과 하루 한 번 자동 백업은 시작을 늦추지 않도록 잠시 뒤 백그라운드에서 한다.
        // 점검에 문제가 있으면 자동 백업은 건너뛴다 — 망가진 DB가 정상 백업을 밀어내면 안 된다.
        // 시험·시연용 스위치: NOTEPADX_SKIP_MAINTENANCE=1 이면 이 백그라운드 점검/정리를 건너뛴다.
        guard ProcessInfo.processInfo.environment["NOTEPADX_SKIP_MAINTENANCE"] != "1" else { return environment }
        Task {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            if let report = try? await database.quickCheck(), report != ["ok"] {
                environment.integrityProblem = report.prefix(3).joined(separator: "\n")
                return
            }
            // 업데이트로 새 저장 방식이 들어왔으면 기존 버전 기록의 중복 이미지를 한 번 정리한다.
            // 위에서 이미 안전 백업을 만들었다면 같은 백업을 또 만들지 않는다.
            await BackupCoordinator.shared.compactStorageIfNeeded(alreadyBackedUp: tookSafetySnapshot)
            await BackupCoordinator.shared.backupIfDue()
        }
        return environment
    }
}
