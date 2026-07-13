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
        let database = try DatabaseManager(databaseURL: databaseURL)
        try await SchemaMigrator.migrate(database)

        let noteRepository = SQLiteNoteRepository(db: database)
        let folderRepository = SQLiteFolderRepository(db: database)
        let tagRepository = SQLiteTagRepository(db: database)
        let revisionRepository = SQLiteNoteRevisionRepository(db: database)
        let syncStateRepository = SQLiteSyncStateRepository(db: database)
        let searchIndex = SearchIndexService(db: database)
        let noteUseCase = NoteUseCase(noteRepository: noteRepository, searchIndex: searchIndex)

        let folderAccessService = FolderAccessService()
        folderAccessService.restoreAccessIfAvailable()
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
        return environment
    }
}
