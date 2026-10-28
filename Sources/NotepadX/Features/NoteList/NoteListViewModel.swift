import Foundation

@MainActor
final class NoteListViewModel: ObservableObject {
    @Published var notes: [Note] = []
    @Published var selectedNoteID: UUID?
    @Published var errorMessage: String?

    @Published var searchQuery: String = ""
    @Published var searchResults: [SearchHit] = []
    @Published var searchFilters = SearchFilters()

    /// 체크상자로 여러 메모를 골라 한꺼번에 삭제하는 모드.
    @Published var isSelecting = false
    @Published var checkedNoteIDs: Set<UUID> = []

    /// 영구 삭제로 태그가 자동 정리됐을 때 사이드바가 즉시 반영하도록 ContentView가 연결한다.
    var onTagsChanged: (() -> Void)?

    private let noteUseCase: NoteUseCase
    private let tagUseCase: TagUseCase
    private let searchUseCase: SearchUseCase
    private var searchTask: Task<Void, Never>?
    private var currentFilter: NoteListFilter = .all

    private var externalChangeObserver: NSObjectProtocol?

    init(noteUseCase: NoteUseCase, tagUseCase: TagUseCase, searchUseCase: SearchUseCase) {
        self.noteUseCase = noteUseCase
        self.tagUseCase = tagUseCase
        self.searchUseCase = searchUseCase
        // 빠른 메모·단축어처럼 메인 창 밖에서 메모가 생기면 목록을 다시 불러온다.
        externalChangeObserver = NotificationCenter.default.addObserver(forName: .notesChangedExternally, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.load(filter: self.currentFilter) }
            }
        }
    }

    deinit {
        if let externalChangeObserver { NotificationCenter.default.removeObserver(externalChangeObserver) }
    }

    var isSearching: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 가져오기처럼 밖에서 메모가 한꺼번에 생긴 뒤: 목록을 다시 불러오고 첫 메모를 연다.
    func showImported(_ ids: [UUID]) async {
        await load(filter: currentFilter)
        if let first = ids.first { selectedNoteID = first }
    }

    func load(filter: NoteListFilter) async {
        currentFilter = filter
        do {
            notes = try await noteUseCase.fetchNotes(filter: filter)
            if let selectedNoteID, notes.contains(where: { $0.id == selectedNoteID }) {
                // 선택 유지
            } else {
                selectedNoteID = notes.first?.id
            }
        } catch {
            report(error)
        }
        isSelecting = false
        checkedNoteIDs.removeAll()
    }

    @discardableResult
    func createNote(folderID: UUID?) async -> UUID? {
        do {
            let note = try await noteUseCase.createNote(folderID: folderID)
            notes.insert(note, at: 0)
            selectedNoteID = note.id
            return note.id
        } catch {
            report(error)
            return nil
        }
    }

    /// 새 문서 > 다이어그램 만들기 (스펙: SVG 다이어그램 편집기).
    @discardableResult
    func createDiagram(folderID: UUID?) async -> UUID? {
        do {
            let note = try await noteUseCase.createDiagram(folderID: folderID)
            notes.insert(note, at: 0)
            selectedNoteID = note.id
            return note.id
        } catch {
            report(error)
            return nil
        }
    }

    /// 편집기에서 저장이 성공한 직후 EditorViewModel.onNoteUpdated로 호출된다. 목록 전체를
    /// 다시 조회하지 않고 그 자리에서 제목/미리보기/수정 시각만 갱신해서, 사용자가 타이핑하는
    /// 도중에 목록 순서가 갑자기 바뀌며 시선을 뺏기지 않게 한다.
    func applyExternalUpdate(_ note: Note) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        // 편집기가 저장한 복사본은 열 때 읽어 둔 즐겨찾기·고정 값을 갖고 있을 수 있다 — 목록이 아는
        // 최신 값을 덮어쓰면 별표/핀이 화면에서만 사라진다.
        var updated = note
        updated.isFavorite = notes[index].isFavorite
        updated.isPinned = notes[index].isPinned
        notes[index] = updated
    }

    func toggleFavorite(_ note: Note) async {
        do {
            try await noteUseCase.setFavorite(id: note.id, isFavorite: !note.isFavorite)
            if let index = notes.firstIndex(where: { $0.id == note.id }) {
                notes[index].isFavorite.toggle()
            }
        } catch {
            report(error)
        }
    }

    /// 메모 잠금/해제. 잠그는 건 바로 되지만, 풀 때는 Touch ID/암호 인증을 거친다. 목록에서 바꿔도
    /// 이미 열려 있는 편집기가 곧바로 잠김 화면으로 바뀌도록 알림을 보낸다.
    func toggleLocked(_ note: Note) async {
        let session = NoteLockSession.shared
        let willLock = !note.isLocked
        do {
            if !willLock {
                guard await session.authenticate(reason: "‘\(note.displayTitle)’ 메모의 잠금을 해제합니다") else { return }
            }
            await SaveCoordinator.shared.flushAll()   // 열려 있던 편집 내용이 잠그기 전에 저장되게
            try await noteUseCase.setLocked(id: note.id, isLocked: willLock)
            session.forget(note.id)
            NotificationCenter.default.post(name: .noteLockChanged, object: nil, userInfo: ["id": note.id, "isLocked": willLock])
            await load(filter: currentFilter)
        } catch {
            report(error)
        }
    }

    /// 목록 맨 위에 고정/해제한다. 해제했을 때 원래 날짜 순서 자리로 돌아가야 해서, 화면의 배열을
    /// 직접 주무르지 않고 DB의 정렬 규칙(고정 우선 → 최신순)으로 다시 불러온다. 선택은 유지된다.
    func togglePinned(_ note: Note) async {
        do {
            try await noteUseCase.setPinned(id: note.id, isPinned: !note.isPinned)
            await load(filter: currentFilter)
        } catch {
            report(error)
        }
    }

    /// 메모 목록에서 사이드바 폴더로 드래그 앤 드롭했을 때 호출한다. 지금 보고 있는 화면이
    /// 다른 특정 폴더라면(= 이동 후 이 목록에 더는 속하지 않으면) 그 자리에서 사라져야 하고,
    /// "모든 메모"·"즐겨찾기"·태그·최근 메모처럼 폴더를 가리지 않는 화면이라면 그대로 남되
    /// folderID만 갱신하면 된다.
    func moveNotes(_ ids: Set<UUID>, toFolderID folderID: UUID?) async {
        guard !ids.isEmpty else { return }
        for id in ids {
            do {
                try await noteUseCase.moveNote(id: id, toFolderID: folderID)
            } catch {
                report(error)
            }
        }
        if case .folder(let currentFolderID) = currentFilter, currentFolderID != folderID {
            notes.removeAll { ids.contains($0.id) }
            if let selectedNoteID, ids.contains(selectedNoteID) {
                self.selectedNoteID = notes.first?.id
            }
        } else {
            for index in notes.indices where ids.contains(notes[index].id) {
                notes[index].folderID = folderID
            }
        }
    }

    func moveToTrash(_ note: Note) async {
        do {
            try await noteUseCase.moveToTrash(id: note.id)
            notes.removeAll { $0.id == note.id }
            if selectedNoteID == note.id { selectedNoteID = notes.first?.id }
        } catch {
            report(error)
        }
    }

    func restore(_ note: Note) async {
        do {
            try await noteUseCase.restore(id: note.id)
            notes.removeAll { $0.id == note.id }
            if selectedNoteID == note.id { selectedNoteID = notes.first?.id }
        } catch {
            report(error)
        }
    }

    func deletePermanently(_ note: Note) async {
        await deleteNotesPermanentlyAndPruneOrphanedTags([note.id])
    }

    // MARK: - 선택 모드 (체크상자로 여러 개 한꺼번에 삭제)

    func toggleSelectionMode() {
        isSelecting.toggle()
        if !isSelecting { checkedNoteIDs.removeAll() }
    }

    func toggleChecked(_ noteID: UUID) {
        if checkedNoteIDs.contains(noteID) {
            checkedNoteIDs.remove(noteID)
        } else {
            checkedNoteIDs.insert(noteID)
        }
    }

    func selectAllVisible() {
        checkedNoteIDs = Set(notes.map(\.id))
    }

    func deselectAll() {
        checkedNoteIDs.removeAll()
    }

    /// 선택 모드에서 "삭제"를 눌렀을 때 호출한다. 휴지통 화면이면 영구 삭제(다 쓴 태그도 같이
    /// 정리), 그 외 화면이면 휴지통으로 이동한다(복원할 수 있으니 태그는 그대로 둔다).
    func deleteCheckedNotes(permanently: Bool) async {
        let ids = checkedNoteIDs
        guard !ids.isEmpty else { return }

        if permanently {
            await deleteNotesPermanentlyAndPruneOrphanedTags(ids)
        } else {
            for id in ids {
                do {
                    try await noteUseCase.moveToTrash(id: id)
                } catch {
                    report(error)
                }
            }
            notes.removeAll { ids.contains($0.id) }
            if let selectedNoteID, ids.contains(selectedNoteID) {
                self.selectedNoteID = notes.first?.id
            }
        }

        checkedNoteIDs.removeAll()
        isSelecting = false
    }

    /// 노트를 영구 삭제하고, 그 노트들에만 붙어 있어서 이제 어떤 노트에도 안 쓰이는 태그를
    /// 자동으로 지운다. 휴지통 이동(소프트 삭제)에서는 이 정리를 하지 않는다 — 나중에 복원하면
    /// 태그도 같이 돌아와야 하는데, 여기서 태그를 지워버리면 복원 후 태그가 사라진 것처럼 보인다.
    private func deleteNotesPermanentlyAndPruneOrphanedTags(_ ids: Set<UUID>) async {
        var candidateTagIDs = Set<UUID>()
        for id in ids {
            if let tags = try? await tagUseCase.tags(forNote: id) {
                candidateTagIDs.formUnion(tags.map(\.id))
            }
        }

        for id in ids {
            do {
                try await noteUseCase.deletePermanently(id: id)
            } catch {
                report(error)
            }
        }
        notes.removeAll { ids.contains($0.id) }
        if let selectedNoteID, ids.contains(selectedNoteID) {
            self.selectedNoteID = notes.first?.id
        }

        var didPruneAnyTag = false
        for tagID in candidateTagIDs {
            guard let count = try? await tagUseCase.noteCount(tagID: tagID), count == 0 else { continue }
            try? await tagUseCase.delete(id: tagID)
            didPruneAnyTag = true
        }
        if didPruneAnyTag {
            onTagsChanged?()
        }
    }

    // MARK: - 검색

    /// 검색어/필터 입력마다 200ms debounce 후 실행한다. 짧은 debounce는 FTS5 질의가
    /// DB 트랜잭션 쓰기와 달리 가벼운 읽기 전용 작업이라 반응성을 우선했다.
    func performSearch() {
        searchTask?.cancel()
        guard isSearching else {
            searchResults = []
            return
        }
        let query = searchQuery
        let filters = searchFilters
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            do {
                let results = try await searchUseCase.search(query: query, filters: filters)
                guard !Task.isCancelled else { return }
                searchResults = results
                if let selectedNoteID, results.contains(where: { $0.noteID == selectedNoteID }) {
                    // 선택 유지
                } else {
                    selectedNoteID = results.first?.noteID
                }
            } catch {
                report(error)
            }
        }
    }

    func clearSearch() {
        searchTask?.cancel()
        searchQuery = ""
        searchResults = []
    }

    private func report(_ error: Error) {
        errorMessage = (error as? AppError)?.errorDescription ?? error.localizedDescription
    }
}
