import Foundation

@MainActor
final class OneDriveViewModel: ObservableObject {
    @Published var isSyncing = false
    @Published var conflicts: [SyncConflict] = []
    @Published var errorMessage: String?
    @Published var lastSyncSummary: String?

    let folderAccessService: FolderAccessService
    private let syncUseCase: OneDriveSyncUseCase
    private let noteUseCase: NoteUseCase

    init(folderAccessService: FolderAccessService, syncUseCase: OneDriveSyncUseCase, noteUseCase: NoteUseCase) {
        self.folderAccessService = folderAccessService
        self.syncUseCase = syncUseCase
        self.noteUseCase = noteUseCase
    }

    var folderURL: URL? { folderAccessService.folderURL }
    var needsReselection: Bool { folderAccessService.needsReselection }

    func chooseFolder() {
        folderAccessService.presentFolderPicker()
    }

    func forgetFolder() {
        folderAccessService.forgetFolder()
    }

    /// 로컬에 있는 모든(휴지통 제외) 노트를 훑어 각각 sync를 돌린다. 충돌은 자동으로
    /// 풀지 않고 목록에 모아 사용자가 하나씩 고르게 한다.
    func syncAll() async {
        guard let root = folderAccessService.folderURL else {
            errorMessage = "먼저 동기화할 폴더를 선택하세요."
            return
        }
        isSyncing = true
        errorMessage = nil
        conflicts = []
        var uploaded = 0
        var downloaded = 0
        var upToDate = 0

        let provider = OneDriveFolderSyncProvider(rootURL: root, deviceID: AppConfig.deviceID)
        do {
            let notes = try await noteUseCase.fetchNotes(filter: .all)
            for note in notes {
                let outcome = try await syncUseCase.sync(noteID: note.id, using: provider)
                switch outcome {
                case .uploaded: uploaded += 1
                case .downloaded: downloaded += 1
                case .upToDate: upToDate += 1
                case .conflict(let conflict): conflicts.append(conflict)
                }
            }
            lastSyncSummary = "업로드 \(uploaded)개 · 다운로드 \(downloaded)개 · 최신 상태 \(upToDate)개 · 충돌 \(conflicts.count)개"
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isSyncing = false
    }

    /// 편집기에서 노트가 저장될 때마다 ContentView가 호출한다. 폴더를 한 번 설정해 두면
    /// 그 뒤로 저장되는 노트들이 "지금 동기화"를 매번 누르지 않아도 자동으로 반영되게 하기
    /// 위함이다. 폴더가 아직 설정되지 않았으면 조용히 아무것도 하지 않는다.
    func syncNoteIfConfigured(_ noteID: UUID) async {
        guard let root = folderAccessService.folderURL else { return }
        let provider = OneDriveFolderSyncProvider(rootURL: root, deviceID: AppConfig.deviceID)
        do {
            let outcome = try await syncUseCase.sync(noteID: noteID, using: provider)
            if case .conflict(let conflict) = outcome, !conflicts.contains(where: { $0.id == conflict.id }) {
                conflicts.append(conflict)
            }
        } catch {
            // 타이핑할 때마다 자동으로 도는 동기화라 실패마다 오류창을 띄우면 방해가 된다
            // (네트워크가 잠깐 끊기거나 OneDrive 폴더가 언마운트된 경우 등). 조용히 넘어가고,
            // 다음 자동저장이나 사용자가 직접 누르는 "지금 동기화"에서 다시 시도된다.
        }
    }

    func resolve(_ conflict: SyncConflict, as resolution: SyncConflictResolution) async {
        guard let root = folderAccessService.folderURL else { return }
        let provider = OneDriveFolderSyncProvider(rootURL: root, deviceID: AppConfig.deviceID)
        do {
            try await syncUseCase.resolveConflict(conflict, resolution: resolution, using: provider)
            conflicts.removeAll { $0.id == conflict.id }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
