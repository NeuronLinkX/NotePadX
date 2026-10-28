import XCTest
@testable import NotepadX

final class BackupClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(_ start: Date) { current = start }
    var now: Date { lock.lock(); defer { lock.unlock() }; return current }
    func advance(_ seconds: TimeInterval) { lock.lock(); current = current.addingTimeInterval(seconds); lock.unlock() }
}

final class DatabaseBackupServiceTests: XCTestCase {
    private var root: URL!
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var clock: BackupClock!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("NotepadXBackupTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suiteName = "NotepadXBackupTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        clock = BackupClock(Date(timeIntervalSince1970: 1_800_000_000))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: suiteName)
    }

    private var supportDirectory: URL { root.appendingPathComponent("support", isDirectory: true) }
    private var attachmentsDirectory: URL { root.appendingPathComponent("attachments", isDirectory: true) }
    private var databaseURL: URL { supportDirectory.appendingPathComponent("NotepadX.sqlite") }

    private func makeService() -> DatabaseBackupService {
        let support = supportDirectory, attachments = attachmentsDirectory, clock = clock!
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return DatabaseBackupService(
            defaults: defaults,
            supportDirectory: { support },
            attachmentsDirectory: { attachments },
            now: { clock.now }
        )
    }

    private func makeDatabase(at url: URL? = nil) async throws -> (DatabaseManager, NoteUseCase) {
        try? FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        let db = try DatabaseManager(databaseURL: url ?? databaseURL)
        try await SchemaMigrator.migrate(db)
        let useCase = NoteUseCase(noteRepository: SQLiteNoteRepository(db: db), searchIndex: SearchIndexService(db: db))
        return (db, useCase)
    }

    private func noteCount(in db: DatabaseManager) async throws -> Int {
        try await db.query("SELECT COUNT(*) FROM note;") { $0.int(0) ?? -1 }.first ?? -1
    }

    // MARK: - 백업 만들기

    func testBackupContainsAllNotesAndPassesIntegrityCheck() async throws {
        let (db, useCase) = try await makeDatabase()
        for _ in 0..<4 { try await useCase.createNote(folderID: nil) }
        let service = makeService()

        let record = try await service.createBackup(from: db, kind: .manual)

        XCTAssertTrue(DatabaseManager.verifyFile(at: record.url))
        XCTAssertGreaterThan(record.byteCount, 0)
        let copy = try DatabaseManager(databaseURL: record.url)
        let copiedCount = try await noteCount(in: copy)
        XCTAssertEqual(copiedCount, 4)
    }

    func testBackupIsStandaloneWithoutWALSidecarFiles() async throws {
        let (db, useCase) = try await makeDatabase()
        try await useCase.createNote(folderID: nil)
        let record = try await makeService().createBackup(from: db, kind: .manual)

        // 헤더 18~19번째 바이트가 1,1이면 WAL이 아닌 일반(단독 파일) 모드다.
        XCTAssertEqual(Array(try Data(contentsOf: record.url).dropFirst(18).prefix(2)), [1, 1])
        XCTAssertFalse(FileManager.default.fileExists(atPath: record.url.path + "-wal"), "백업은 -wal 없이 단독으로 열려야 한다")
        XCTAssertFalse(FileManager.default.fileExists(atPath: record.url.path + "-shm"))
    }

    func testVerifyFileRejectsGarbageAndMissingFiles() throws {
        let garbage = root.appendingPathComponent("garbage.sqlite")
        try Data(repeating: 0x41, count: 4096).write(to: garbage)
        XCTAssertFalse(DatabaseManager.verifyFile(at: garbage))
        XCTAssertFalse(DatabaseManager.verifyFile(at: root.appendingPathComponent("nope.sqlite")))
    }

    func testQuickCheckReportsOKOnHealthyDatabase() async throws {
        let (db, _) = try await makeDatabase()
        let report = try await db.quickCheck()
        XCTAssertEqual(report, ["ok"])
    }

    // MARK: - 이름 / 주기 / 보관

    func testFileNameRoundTripsAndRejectsForeignFiles() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        for kind in BackupKind.allCases {
            let name = DatabaseBackupService.fileName(kind: kind, date: date)
            let parsed = DatabaseBackupService.parse(fileName: name)
            XCTAssertEqual(parsed?.kind, kind)
            XCTAssertEqual(parsed?.date.timeIntervalSince1970 ?? 0, date.timeIntervalSince1970, accuracy: 1)
        }
        XCTAssertNil(DatabaseBackupService.parse(fileName: "NotepadX.sqlite"))
        XCTAssertNil(DatabaseBackupService.parse(fileName: "NotepadX-weird-20260101-000000.sqlite"))
        XCTAssertNil(DatabaseBackupService.parse(fileName: "photo.png"))
    }

    func testAutoBackupDueOnlyAfterTwentyHoursAndWhenEnabled() async throws {
        let (db, _) = try await makeDatabase()
        let service = makeService()
        XCTAssertTrue(service.isAutoBackupDue(), "한 번도 안 했으면 해야 한다")

        try await service.createBackup(from: db, kind: .auto)
        XCTAssertFalse(service.isAutoBackupDue())

        clock.advance(19 * 3600)
        XCTAssertFalse(service.isAutoBackupDue())
        clock.advance(2 * 3600)
        XCTAssertTrue(service.isAutoBackupDue())

        service.isAutoBackupEnabled = false
        XCTAssertFalse(service.isAutoBackupDue(), "끄면 절대 자동으로 하지 않는다")
    }

    func testManualBackupDoesNotResetTheAutoBackupClock() async throws {
        let (db, _) = try await makeDatabase()
        let service = makeService()
        try await service.createBackup(from: db, kind: .manual)
        XCTAssertTrue(service.isAutoBackupDue())
    }

    func testRetentionKeepsNewestAutoBackupsAndNeverDeletesManualOnes() async throws {
        let (db, _) = try await makeDatabase()
        let service = makeService()
        service.keepCount = 2

        let manual = try await service.createBackup(from: db, kind: .manual)
        for _ in 0..<5 {
            clock.advance(60)
            try await service.createBackup(from: db, kind: .auto)
        }

        let records = service.list()
        XCTAssertEqual(records.filter { $0.kind == .auto }.count, 2)
        XCTAssertTrue(records.contains { $0.url.lastPathComponent == manual.url.lastPathComponent }, "수동 백업은 자동 정리 대상이 아니다")
        let newestAuto = records.filter { $0.kind == .auto }.map(\.createdAt).max()
        XCTAssertEqual(newestAuto, clock.now, "가장 최근 것이 남아야 한다")
    }

    func testKeepCountIsClampedToSaneRange() {
        let service = makeService()
        service.keepCount = 0
        XCTAssertEqual(service.keepCount, 1)
        service.keepCount = 9_999
        XCTAssertEqual(service.keepCount, 60)
    }

    // MARK: - 첨부 파일

    func testAttachmentsAreMirroredIntoTheBackupFolderOnce() async throws {
        let (db, _) = try await makeDatabase()
        let file = attachmentsDirectory.appendingPathComponent("abc-123/report.pdf")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("pdf-bytes".utf8).write(to: file)
        let service = makeService()

        try await service.createBackup(from: db, kind: .manual)

        let mirrored = try service.localDirectory().appendingPathComponent("Attachments/abc-123/report.pdf")
        XCTAssertEqual(try Data(contentsOf: mirrored), Data("pdf-bytes".utf8))
    }

    // MARK: - 복원

    func testStageThenApplyRestoreReturnsToTheBackedUpState() async throws {
        let service = makeService()
        let record: BackupRecord
        do {
            let (db, useCase) = try await makeDatabase()
            for _ in 0..<3 { try await useCase.createNote(folderID: nil) }
            record = try await service.createBackup(from: db, kind: .manual)
            for _ in 0..<2 { try await useCase.createNote(folderID: nil) }   // 백업 이후의 변경
            try await service.stageRestore(record, currentDatabase: db)
        }

        XCTAssertTrue(service.hasStagedRestore)
        XCTAssertTrue(service.applyStagedRestore(databaseURL: databaseURL))
        XCTAssertFalse(service.hasStagedRestore)

        let restored = try DatabaseManager(databaseURL: databaseURL)
        let restoredCount = try await noteCount(in: restored)
        XCTAssertEqual(restoredCount, 3, "백업 시점(3개)으로 돌아가야 한다")

        let safety = service.list().first { $0.kind == .preRestore }
        let safetyURL = try XCTUnwrap(safety?.url, "복원 전 현재 상태가 따로 백업돼 있어야 한다")
        let safetyDB = try DatabaseManager(databaseURL: safetyURL)
        let safetyCount = try await noteCount(in: safetyDB)
        XCTAssertEqual(safetyCount, 5, "복원 직전 상태(5개)는 잃지 않는다")
    }

    func testRestoreNeverStartsIfTheBackupIsCorrupt() async throws {
        let (db, useCase) = try await makeDatabase()
        try await useCase.createNote(folderID: nil)
        let service = makeService()
        let bad = try service.localDirectory().appendingPathComponent(DatabaseBackupService.fileName(kind: .manual, date: clock.now))
        try Data(repeating: 0x42, count: 8192).write(to: bad)
        let record = BackupRecord(url: bad, kind: .manual, createdAt: clock.now, byteCount: 8192, isExternal: false)

        do {
            try await service.stageRestore(record, currentDatabase: db)
            XCTFail("손상된 백업으로 복원이 시작되면 안 된다")
        } catch {
            XCTAssertEqual(error as? BackupError, .backupUnreadable)
        }
        XCTAssertFalse(service.hasStagedRestore)
        let stillThere = try await noteCount(in: db)
        XCTAssertEqual(stillThere, 1, "현재 데이터는 그대로")
    }

    func testApplyStagedRestoreRefusesACorruptStagedFileAndKeepsTheLiveDatabase() async throws {
        let service = makeService()
        do {
            let (_, useCase) = try await makeDatabase()
            try await useCase.createNote(folderID: nil)
        }
        try Data(repeating: 0x43, count: 8192).write(to: supportDirectory.appendingPathComponent("restore-staged.sqlite"))

        XCTAssertFalse(service.applyStagedRestore(databaseURL: databaseURL))

        let live = try DatabaseManager(databaseURL: databaseURL)
        let liveCount = try await noteCount(in: live)
        XCTAssertEqual(liveCount, 1)
        XCTAssertFalse(service.hasStagedRestore, "손상된 예약 파일은 지워져야 한다")
    }

    func testApplyStagedRestoreDoesNothingWhenNothingIsStaged() async throws {
        let service = makeService()
        XCTAssertFalse(service.applyStagedRestore(databaseURL: databaseURL))
    }

    // MARK: - 외부 폴더

    func testBackupIsAlsoCopiedToTheExternalFolder() async throws {
        let (db, useCase) = try await makeDatabase()
        try await useCase.createNote(folderID: nil)
        let external = root.appendingPathComponent("external", isDirectory: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        let service = makeService()
        try service.setExternalFolder(external)

        let record = try await service.createBackup(from: db, kind: .manual)

        let copy = external.appendingPathComponent(record.url.lastPathComponent)
        XCTAssertTrue(DatabaseManager.verifyFile(at: copy))
        XCTAssertTrue(service.list().contains { $0.isExternal })
        XCTAssertNil(service.lastExternalError)
    }

    func testLocalBackupSucceedsEvenWhenTheExternalFolderDisappears() async throws {
        let (db, _) = try await makeDatabase()
        let external = root.appendingPathComponent("gone", isDirectory: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        let service = makeService()
        try service.setExternalFolder(external)
        try FileManager.default.removeItem(at: external)

        let record = try await service.createBackup(from: db, kind: .manual)

        XCTAssertTrue(DatabaseManager.verifyFile(at: record.url), "외부 폴더가 사라져도 로컬 백업은 만들어져야 한다")
    }

    // MARK: - 마이그레이션 판단

    func testPendingStateDistinguishesFreshExistingAndOutdatedDatabases() async throws {
        let fresh = try DatabaseManager(databaseURL: root.appendingPathComponent("fresh.sqlite"))
        let freshState = try await SchemaMigrator.pendingState(fresh)
        XCTAssertFalse(freshState.hasExistingData, "빈 새 DB는 지킬 데이터가 없다")

        let (db, _) = try await makeDatabase()
        let current = try await SchemaMigrator.pendingState(db)
        XCTAssertTrue(current.hasExistingData)
        XCTAssertEqual(current.pendingCount, 0)

        let latest = SchemaMigrator.migrations.map(\.version).max() ?? 0
        try await db.execute("DELETE FROM schema_version WHERE version = ?;", [.int(Int64(latest))])
        let outdated = try await SchemaMigrator.pendingState(db)
        XCTAssertEqual(outdated.pendingCount, 1, "마지막 버전이 빠지면 업데이트 1개가 남은 것으로 본다")
    }
}
