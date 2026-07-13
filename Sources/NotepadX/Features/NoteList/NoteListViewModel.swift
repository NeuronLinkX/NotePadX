import Foundation

@MainActor
final class NoteListViewModel: ObservableObject {
    @Published var notes: [Note] = []
    @Published var selectedNoteID: UUID?
    @Published var errorMessage: String?

    @Published var searchQuery: String = ""
    @Published var searchResults: [SearchHit] = []
    @Published var searchFilters = SearchFilters()

    private let noteUseCase: NoteUseCase
    private let searchUseCase: SearchUseCase
    private var searchTask: Task<Void, Never>?

    init(noteUseCase: NoteUseCase, searchUseCase: SearchUseCase) {
        self.noteUseCase = noteUseCase
        self.searchUseCase = searchUseCase
    }

    var isSearching: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func load(filter: NoteListFilter) async {
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

    /// 편집기에서 저장이 성공한 직후 EditorViewModel.onNoteUpdated로 호출된다. 목록 전체를
    /// 다시 조회하지 않고 그 자리에서 제목/미리보기/수정 시각만 갱신해서, 사용자가 타이핑하는
    /// 도중에 목록 순서가 갑자기 바뀌며 시선을 뺏기지 않게 한다.
    func applyExternalUpdate(_ note: Note) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[index] = note
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
        do {
            try await noteUseCase.deletePermanently(id: note.id)
            notes.removeAll { $0.id == note.id }
            if selectedNoteID == note.id { selectedNoteID = notes.first?.id }
        } catch {
            report(error)
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
