import AppKit
import Foundation

@MainActor
final class BackupSettingsViewModel: ObservableObject {
    @Published var isAutoBackupEnabled: Bool {
        didSet { service.isAutoBackupEnabled = isAutoBackupEnabled }
    }
    @Published var keepCount: Int {
        didSet {
            service.keepCount = keepCount
            service.prune()
            reload()
        }
    }
    @Published private(set) var records: [BackupRecord] = []
    @Published private(set) var isWorking = false
    @Published private(set) var isReady = false
    @Published private(set) var lastAutoBackupText = "아직 없음"
    @Published private(set) var externalPath: String?
    @Published private(set) var externalError: String?
    @Published private(set) var hasStagedRestore = false
    @Published var checkResult: String?
    @Published var infoMessage: String?
    @Published var errorMessage: String?
    @Published private(set) var storageStats: RevisionStorageStats?
    @Published private(set) var isCompacting = false
    @Published var compactionMessage: String?
    @Published var restoreCandidate: BackupRecord?
    @Published var showQuitNotice = false

    private let service: DatabaseBackupService
    private let coordinator: BackupCoordinator

    init(coordinator: BackupCoordinator = .shared) {
        self.coordinator = coordinator
        self.service = coordinator.service
        self.isAutoBackupEnabled = coordinator.service.isAutoBackupEnabled
        self.keepCount = coordinator.service.keepCount
        reload()
        Task { await refreshReadiness() }
    }

    var backupFolderURL: URL? { try? service.localDirectory() }

    func reload() {
        records = service.list()
        externalPath = service.externalFolderPath
        externalError = service.lastExternalError
        hasStagedRestore = service.hasStagedRestore
        if let last = service.lastAutoBackupDate {
            lastAutoBackupText = last.formatted(date: .abbreviated, time: .shortened)
        }
    }

    func refreshReadiness() async {
        isReady = await coordinator.isReady
        if isReady { await reloadStorageStats() }
    }

    func reloadStorageStats() async {
        storageStats = try? await coordinator.storageStats()
    }

    func compactStorage() {
        guard !isWorking, !isCompacting else { return }
        isCompacting = true
        compactionMessage = nil
        Task {
            defer { isCompacting = false }
            do {
                let report = try await coordinator.compactStorage()
                compactionMessage = report.convertedRevisions == 0
                    ? "정리할 항목이 없습니다."
                    : "버전 기록 \(report.convertedRevisions)개를 정리했습니다 — \(Self.sizeText(report.databaseBytesBefore)) → \(Self.sizeText(report.databaseBytesAfter)) (\(Self.sizeText(report.savedBytes)) 절약)"
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            await reloadStorageStats()
            reload()
        }
    }

    func backupNow() {
        guard !isWorking else { return }
        isWorking = true
        infoMessage = nil
        Task {
            defer { isWorking = false }
            do {
                let record = try await coordinator.backupNow(kind: .manual)
                infoMessage = "백업을 만들었습니다 (\(Self.sizeText(record.byteCount)))."
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            reload()
        }
    }

    func runIntegrityCheck() {
        guard !isWorking else { return }
        isWorking = true
        checkResult = nil
        Task {
            defer { isWorking = false }
            do {
                let report = try await coordinator.integrityReport()
                checkResult = report == ["ok"] ? "문제 없음 — 데이터베이스가 온전합니다." : "문제 발견: \(report.prefix(3).joined(separator: " / "))"
            } catch {
                checkResult = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func chooseExternalFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "백업을 추가로 보관할 폴더를 고르세요. OneDrive·iCloud Drive 같은 클라우드 폴더를 고르면 Mac이 고장 나도 메모를 지킬 수 있습니다."
        panel.prompt = "선택"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try service.setExternalFolder(url)
            infoMessage = "다음 백업부터 이 폴더에도 복사합니다."
        } catch {
            errorMessage = "폴더를 저장하지 못했습니다: \(error.localizedDescription)"
        }
        reload()
    }

    func clearExternalFolder() {
        service.clearExternalFolder()
        reload()
    }

    func revealBackupFolder() {
        guard let url = backupFolderURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func delete(_ record: BackupRecord) {
        do {
            try service.delete(record)
        } catch {
            errorMessage = "삭제하지 못했습니다: \(error.localizedDescription)"
        }
        reload()
    }

    func performRestore() {
        guard let record = restoreCandidate, !isWorking else { return }
        restoreCandidate = nil
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await coordinator.stageRestore(record)
                showQuitNotice = true
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            reload()
        }
    }

    func cancelStagedRestore() {
        service.cancelStagedRestore()
        reload()
    }

    func quitNow() {
        NSApp.terminate(nil)
    }

    static func sizeText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
