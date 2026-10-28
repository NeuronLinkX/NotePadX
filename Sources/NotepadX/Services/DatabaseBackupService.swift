import Foundation

enum BackupKind: String, Sendable, CaseIterable {
    case auto
    case manual
    case preMigration = "premigrate"
    case preRestore = "prerestore"

    var label: String {
        switch self {
        case .auto: return "자동"
        case .manual: return "수동"
        case .preMigration: return "업데이트 전"
        case .preRestore: return "복원 전"
        }
    }

    /// 자동으로 지워도 되는 보관 개수. 사용자가 직접 만든 수동 백업은 절대 자동으로 지우지 않는다.
    func retentionLimit(autoKeepCount: Int) -> Int? {
        switch self {
        case .auto: return autoKeepCount
        case .preMigration, .preRestore: return 3
        case .manual: return nil
        }
    }
}

struct BackupRecord: Identifiable, Equatable, Sendable {
    let url: URL
    let kind: BackupKind
    let createdAt: Date
    let byteCount: Int64
    let isExternal: Bool
    var id: URL { url }
}

enum BackupError: LocalizedError, Equatable {
    case notReady
    case backupUnreadable
    case restoreFailed

    var errorDescription: String? {
        switch self {
        case .notReady:
            return "데이터베이스가 아직 준비되지 않았습니다. 잠시 후 다시 시도해 주세요."
        case .backupUnreadable:
            return "이 백업 파일을 열 수 없거나 손상되어 있습니다. 현재 데이터는 그대로 유지됩니다."
        case .restoreFailed:
            return "복원을 준비하지 못했습니다. 현재 데이터는 그대로 유지됩니다."
        }
    }
}

/// 메모 데이터베이스의 백업/복원. 이 앱의 모든 메모·버전 기록·태그가 SQLite 파일 하나에 들어 있어서,
/// 파일이 망가지거나 컨테이너가 지워지면 전부 잃는다 — 그래서 하루 한 번 자동으로, 그리고 위험한
/// 작업(스키마 변경, 복원) 직전에 항상 스냅샷을 남긴다. 파일 입출력과 설정만 다루고 UI는 모른다.
/// UserDefaults는 문서상 스레드 안전하지만 아직 Sendable로 표시돼 있지 않아 `@unchecked`로 선언한다.
struct DatabaseBackupService: @unchecked Sendable {
    static let autoBackupInterval: TimeInterval = 20 * 3600
    static let defaultKeepCount = 7
    static let keepCountRange = 1...60

    private static let autoEnabledKey = "NotepadX.backup.autoEnabled"
    private static let keepCountKey = "NotepadX.backup.keepCount"
    private static let lastAutoKey = "NotepadX.backup.lastAuto"
    private static let externalBookmarkKey = "NotepadX.backup.externalBookmark"
    private static let externalErrorKey = "NotepadX.backup.externalError"

    private let defaults: UserDefaults
    private let supportDirectory: @Sendable () throws -> URL
    private let attachmentsDirectory: @Sendable () throws -> URL
    private let now: @Sendable () -> Date

    init(
        defaults: UserDefaults = AppConfig.defaults,
        supportDirectory: @escaping @Sendable () throws -> URL = { try AppConfig.applicationSupportURL() },
        attachmentsDirectory: @escaping @Sendable () throws -> URL = { try AppConfig.attachmentsDirectoryURL() },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.defaults = defaults
        self.supportDirectory = supportDirectory
        self.attachmentsDirectory = attachmentsDirectory
        self.now = now
    }

    // MARK: - 설정

    var isAutoBackupEnabled: Bool {
        get { defaults.object(forKey: Self.autoEnabledKey) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Self.autoEnabledKey) }
    }

    var keepCount: Int {
        get {
            let stored = defaults.object(forKey: Self.keepCountKey) as? Int ?? Self.defaultKeepCount
            return min(max(stored, Self.keepCountRange.lowerBound), Self.keepCountRange.upperBound)
        }
        nonmutating set {
            defaults.set(min(max(newValue, Self.keepCountRange.lowerBound), Self.keepCountRange.upperBound), forKey: Self.keepCountKey)
        }
    }

    var lastAutoBackupDate: Date? {
        let stored = defaults.double(forKey: Self.lastAutoKey)
        return stored > 0 ? Date(timeIntervalSince1970: stored) : nil
    }

    /// 마지막 외부 폴더 복사가 실패했다면 그 이유(성공하면 nil).
    var lastExternalError: String? { defaults.string(forKey: Self.externalErrorKey) }

    func isAutoBackupDue() -> Bool {
        guard isAutoBackupEnabled else { return false }
        guard let last = lastAutoBackupDate else { return true }
        return now().timeIntervalSince(last) >= Self.autoBackupInterval
    }

    // MARK: - 폴더

    func localDirectory() throws -> URL {
        let directory = try supportDirectory().appendingPathComponent("Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// 사용자가 고른 외부(클라우드 등) 백업 폴더. 샌드박스 안에서도 다시 열 수 있게 보안 범위
    /// 북마크로 저장한다.
    func setExternalFolder(_ url: URL) throws {
        let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(bookmark, forKey: Self.externalBookmarkKey)
        defaults.removeObject(forKey: Self.externalErrorKey)
    }

    func clearExternalFolder() {
        defaults.removeObject(forKey: Self.externalBookmarkKey)
        defaults.removeObject(forKey: Self.externalErrorKey)
    }

    var hasExternalFolder: Bool { defaults.data(forKey: Self.externalBookmarkKey) != nil }

    var externalFolderPath: String? { withExternalFolder { $0.path } ?? nil }

    private func withExternalFolder<T>(_ body: (URL) throws -> T) rethrows -> T? {
        guard let data = defaults.data(forKey: Self.externalBookmarkKey) else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) else {
            return nil
        }
        guard url.startAccessingSecurityScopedResource() else { return nil }
        defer { url.stopAccessingSecurityScopedResource() }
        return try body(url)
    }

    // MARK: - 파일 이름

    private static let nameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    static func fileName(kind: BackupKind, date: Date) -> String {
        "NotepadX-\(kind.rawValue)-\(nameFormatter.string(from: date)).sqlite"
    }

    static func parse(fileName: String) -> (kind: BackupKind, date: Date)? {
        guard fileName.hasPrefix("NotepadX-"), fileName.hasSuffix(".sqlite") else { return nil }
        let core = fileName.dropFirst("NotepadX-".count).dropLast(".sqlite".count)
        let parts = core.split(separator: "-", maxSplits: 1).map(String.init)
        guard parts.count == 2, let kind = BackupKind(rawValue: parts[0]), let date = nameFormatter.date(from: parts[1]) else {
            return nil
        }
        return (kind, date)
    }

    // MARK: - 만들기

    @discardableResult
    func createBackup(from database: DatabaseManager, kind: BackupKind) async throws -> BackupRecord {
        let directory = try localDirectory()
        let date = now()
        let destination = directory.appendingPathComponent(Self.fileName(kind: kind, date: date))

        try await database.backup(to: destination)
        guard DatabaseManager.verifyFile(at: destination) else {
            try? FileManager.default.removeItem(at: destination)
            throw BackupError.backupUnreadable
        }
        try? mirrorAttachments(into: directory)

        // 외부 폴더 복사가 실패해도(오프라인, 폴더 삭제 등) 로컬 백업은 이미 안전하므로 전체를
        // 실패시키지 않고, 이유만 기록해 설정 화면에서 보여준다.
        if hasExternalFolder {
            do {
                let copied: Bool? = try withExternalFolder { external in
                    let target = external.appendingPathComponent(destination.lastPathComponent)
                    try? FileManager.default.removeItem(at: target)
                    try FileManager.default.copyItem(at: destination, to: target)
                    try? mirrorAttachments(into: external)
                    return true
                }
                if copied == nil {
                    defaults.set("외부 백업 폴더에 접근할 수 없습니다. 폴더를 다시 선택해 주세요.", forKey: Self.externalErrorKey)
                } else {
                    defaults.removeObject(forKey: Self.externalErrorKey)
                }
            } catch {
                defaults.set(error.localizedDescription, forKey: Self.externalErrorKey)
            }
        }

        if kind == .auto { defaults.set(date.timeIntervalSince1970, forKey: Self.lastAutoKey) }
        prune()

        let size = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        return BackupRecord(url: destination, kind: kind, createdAt: date, byteCount: size, isExternal: false)
    }

    /// 첨부 파일(PDF·문서 등)은 DB 밖에 따로 저장되므로 백업 폴더의 `Attachments/`에 없는 것만
    /// 복사해 둔다 — 첨부는 한 번 저장되면 바뀌지 않아서 매번 전부 복사할 필요가 없다.
    func mirrorAttachments(into root: URL) throws {
        let source = try attachmentsDirectory()
        try Self.copyMissingFiles(from: source, to: root.appendingPathComponent("Attachments", isDirectory: true))
    }

    private static func copyMissingFiles(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: source.path) else { return }
        guard let enumerator = fileManager.enumerator(at: source, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        let basePath = source.standardizedFileURL.path
        for case let fileURL as URL in enumerator {
            if (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { continue }
            let relative = String(fileURL.standardizedFileURL.path.dropFirst(basePath.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let target = destination.appendingPathComponent(relative)
            if fileManager.fileExists(atPath: target.path) { continue }
            try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.copyItem(at: fileURL, to: target)
        }
    }

    // MARK: - 목록 / 정리

    func list() -> [BackupRecord] {
        var records: [BackupRecord] = []
        if let directory = try? localDirectory() {
            records += Self.records(in: directory, isExternal: false)
        }
        if let external = withExternalFolder({ Self.records(in: $0, isExternal: true) }) {
            records += external
        }
        return records.sorted { $0.createdAt > $1.createdAt }
    }

    private static func records(in directory: URL, isExternal: Bool) -> [BackupRecord] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return urls.compactMap { url in
            guard let parsed = parse(fileName: url.lastPathComponent) else { return nil }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            return BackupRecord(url: url, kind: parsed.kind, createdAt: parsed.date, byteCount: size, isExternal: isExternal)
        }
    }

    /// 종류별 보관 개수를 넘는 오래된 백업을 지운다(수동 백업은 제외).
    func prune() {
        let limit = keepCount
        func prune(in directory: URL, isExternal: Bool) {
            let records = Self.records(in: directory, isExternal: isExternal)
            for kind in BackupKind.allCases {
                guard let maxCount = kind.retentionLimit(autoKeepCount: limit) else { continue }
                let ofKind = records.filter { $0.kind == kind }.sorted { $0.createdAt > $1.createdAt }
                for stale in ofKind.dropFirst(maxCount) {
                    try? FileManager.default.removeItem(at: stale.url)
                }
            }
        }
        if let directory = try? localDirectory() { prune(in: directory, isExternal: false) }
        _ = withExternalFolder { prune(in: $0, isExternal: true) }
    }

    func delete(_ record: BackupRecord) throws {
        if record.isExternal {
            _ = try withExternalFolder { _ in try FileManager.default.removeItem(at: record.url) }
        } else {
            try FileManager.default.removeItem(at: record.url)
        }
    }

    // MARK: - 복원 (2단계)

    private func stagedURL() throws -> URL {
        try supportDirectory().appendingPathComponent("restore-staged.sqlite")
    }

    var hasStagedRestore: Bool {
        (try? stagedURL()).map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    /// 1단계: 고른 백업을 검증해 임시 자리에 복사해 둔다. DB가 열려 있는 동안에는 파일을 바꿀 수 없으므로
    /// 실제 교체는 다음 실행 때 DB를 열기 전에 `applyStagedRestore`가 한다. 현재 데이터는 먼저
    /// "복원 전" 백업으로 남기고, 그게 실패하면 복원 자체를 시작하지 않는다.
    func stageRestore(_ record: BackupRecord, currentDatabase: DatabaseManager) async throws {
        let staged = try stagedURL()
        try? FileManager.default.removeItem(at: staged)

        do {
            if record.isExternal {
                let copied: Bool? = try withExternalFolder { external in
                    try Self.copyMissingFiles(
                        from: external.appendingPathComponent("Attachments", isDirectory: true),
                        to: try localDirectory().appendingPathComponent("Attachments", isDirectory: true)
                    )
                    try FileManager.default.copyItem(at: record.url, to: staged)
                    return true
                }
                guard copied != nil else { throw BackupError.restoreFailed }
            } else {
                try FileManager.default.copyItem(at: record.url, to: staged)
            }
        } catch {
            try? FileManager.default.removeItem(at: staged)
            throw BackupError.restoreFailed
        }

        guard DatabaseManager.verifyFile(at: staged) else {
            try? FileManager.default.removeItem(at: staged)
            throw BackupError.backupUnreadable
        }
        do {
            try await createBackup(from: currentDatabase, kind: .preRestore)
        } catch {
            try? FileManager.default.removeItem(at: staged)
            throw BackupError.restoreFailed
        }
    }

    func cancelStagedRestore() {
        if let staged = try? stagedURL() { try? FileManager.default.removeItem(at: staged) }
    }

    /// 2단계: 앱이 켜질 때 DB를 열기 **전에** 호출한다. 준비된 백업이 있으면 현재 DB(와 -wal/-shm)를
    /// 지우고 그 자리에 백업을 놓는다. 현재 데이터는 이미 "복원 전" 백업에 들어 있다. 교체했으면 true.
    @discardableResult
    func applyStagedRestore(databaseURL: URL) -> Bool {
        guard let staged = try? stagedURL(), FileManager.default.fileExists(atPath: staged.path) else { return false }
        guard DatabaseManager.verifyFile(at: staged) else {
            try? FileManager.default.removeItem(at: staged)
            return false
        }
        let fileManager = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            try? fileManager.removeItem(atPath: databaseURL.path + suffix)
        }
        do {
            try fileManager.moveItem(at: staged, to: databaseURL)
        } catch {
            return false
        }
        if let directory = try? localDirectory(), let live = try? attachmentsDirectory() {
            try? Self.copyMissingFiles(from: directory.appendingPathComponent("Attachments", isDirectory: true), to: live)
        }
        return true
    }
}

/// 앱 전체가 공유하는 백업 창구. 설정 화면(별도 Settings 씬)은 AppEnvironment에 접근할 수 없어서,
/// 부트스트랩이 끝나면 여기에 DB를 등록해 두고 양쪽이 이걸 거쳐 쓴다.
actor BackupCoordinator {
    static let shared = BackupCoordinator()

    let service = DatabaseBackupService()
    private var database: DatabaseManager?

    var isReady: Bool { database != nil }

    func configure(database: DatabaseManager) {
        self.database = database
    }

    @discardableResult
    func backupNow(kind: BackupKind = .manual) async throws -> BackupRecord {
        guard let database else { throw BackupError.notReady }
        return try await service.createBackup(from: database, kind: kind)
    }

    /// 하루 한 번(마지막 자동 백업 후 20시간 이상) 자동 백업. 실패해도 앱 동작에는 영향이 없다.
    func backupIfDue() async {
        guard let database, service.isAutoBackupDue() else { return }
        _ = try? await service.createBackup(from: database, kind: .auto)
    }

    func integrityReport() async throws -> [String] {
        guard let database else { throw BackupError.notReady }
        return try await database.quickCheck()
    }

    func stageRestore(_ record: BackupRecord) async throws {
        guard let database else { throw BackupError.notReady }
        try await service.stageRestore(record, currentDatabase: database)
    }

    // MARK: - 저장 공간

    func storageStats() async throws -> RevisionStorageStats {
        guard let database else { throw BackupError.notReady }
        return try await RevisionStorageService.stats(database)
    }

    /// 버전 기록의 이미지 중복을 정리한다. 기존 기록을 다시 쓰는 작업이므로 먼저 안전 백업을 만든다
    /// (이번 실행에서 이미 만들었다면 `alreadyBackedUp`으로 건너뛴다).
    func compactStorage(alreadyBackedUp: Bool = false) async throws -> RevisionCompactionReport {
        guard let database else { throw BackupError.notReady }
        if !alreadyBackedUp {
            try await service.createBackup(from: database, kind: .preMigration)
        }
        return try await RevisionStorageService.compact(database)
    }

    /// 시작 후 백그라운드에서: 정리할 게 있을 때만 정리한다. 실패해도 앱 동작에는 영향이 없다.
    func compactStorageIfNeeded(alreadyBackedUp: Bool) async {
        guard let database, (try? await RevisionStorageService.needsCompaction(database)) == true else { return }
        _ = try? await compactStorage(alreadyBackedUp: alreadyBackedUp)
    }
}
