import SwiftUI

struct NoteListView: View {
    @ObservedObject var viewModel: NoteListViewModel
    let selection: SidebarSelection
    let currentFolderID: UUID?
    let availableFolders: [Folder]
    let availableTags: [Tag]

    @State private var isShowingBulkDeleteConfirm = false

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        Group {
            if viewModel.isSearching {
                searchResultsList
            } else {
                noteList
            }
        }
        .navigationTitle(viewModel.isSearching ? "검색 결과" : listTitle)
        .searchable(text: $viewModel.searchQuery, placement: .toolbar, prompt: "제목, 본문, 코드, 태그 검색")
        .toolbar {
            if viewModel.isSelecting {
                selectionToolbarContent
            } else {
                ToolbarItem {
                    filterMenu
                }
                ToolbarItem {
                    Button {
                        viewModel.toggleSelectionMode()
                    } label: {
                        Label("여러 개 선택", systemImage: "checkmark.circle")
                    }
                    .disabled(viewModel.notes.isEmpty || viewModel.isSearching)
                }
                ToolbarItem {
                    Button {
                        Task { await viewModel.createNote(folderID: currentFolderID) }
                    } label: {
                        Label("새 메모", systemImage: "square.and.pencil")
                    }
                    .disabled(selection == .trash)
                }
            }
        }
        .task(id: selection) {
            await viewModel.load(filter: selection.noteListFilter)
        }
        .onChange(of: viewModel.searchQuery) { _, _ in
            viewModel.performSearch()
            if viewModel.isSelecting { viewModel.toggleSelectionMode() }
        }
        .onChange(of: viewModel.searchFilters) { _, _ in viewModel.performSearch() }
        .confirmationDialog(
            selection == .trash
                ? "\(viewModel.checkedNoteIDs.count)개를 완전히 삭제할까요?"
                : "\(viewModel.checkedNoteIDs.count)개를 휴지통으로 이동할까요?",
            isPresented: $isShowingBulkDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(selection == .trash ? "완전히 삭제" : "휴지통으로 이동", role: .destructive) {
                Task { await viewModel.deleteCheckedNotes(permanently: selection == .trash) }
            }
            Button("취소", role: .cancel) {}
        } message: {
            if selection == .trash {
                Text("완전히 삭제하면 되돌릴 수 없습니다. 이 메모에만 붙어 있던 태그도 함께 정리됩니다.")
            }
        }
        .alert("오류", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    /// `SidebarSelection.title`은 폴더/태그처럼 실제 이름이 있는 항목도 "폴더"/"태그"라는
    /// 자리표시자만 돌려준다(그 enum은 UUID만 들고 있어 이름을 모른다) — 여기서 실제
    /// 이름으로 바꿔서 보여준다. 목록에 없는(방금 삭제된 등) id는 자리표시자로 자연히 대체된다.
    private var listTitle: String {
        switch selection {
        case .folder(let id):
            return availableFolders.first(where: { $0.id == id })?.name ?? selection.title
        case .tag(let id):
            return availableTags.first(where: { $0.id == id })?.name ?? selection.title
        default:
            return selection.title
        }
    }

    @ToolbarContentBuilder
    private var selectionToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("취소") { viewModel.toggleSelectionMode() }
        }
        ToolbarItem {
            Button(viewModel.checkedNoteIDs.count == viewModel.notes.count ? "선택 해제" : "전체 선택") {
                if viewModel.checkedNoteIDs.count == viewModel.notes.count {
                    viewModel.deselectAll()
                } else {
                    viewModel.selectAllVisible()
                }
            }
        }
        ToolbarItem {
            Button(role: .destructive) {
                isShowingBulkDeleteConfirm = true
            } label: {
                Label(
                    viewModel.checkedNoteIDs.isEmpty
                        ? (selection == .trash ? "완전히 삭제" : "삭제")
                        : "\(selection == .trash ? "완전히 삭제" : "삭제") (\(viewModel.checkedNoteIDs.count))",
                    systemImage: "trash"
                )
            }
            .disabled(viewModel.checkedNoteIDs.isEmpty)
        }
    }

    private var noteList: some View {
        List(selection: $viewModel.selectedNoteID) {
            ForEach(viewModel.notes) { note in
                if viewModel.isSelecting {
                    row(for: note)
                } else {
                    row(for: note).tag(note.id)
                }
            }
        }
        .listStyle(.inset)
        .overlay {
            if viewModel.notes.isEmpty {
                ContentUnavailableView(
                    selection == .trash ? "휴지통이 비어 있습니다" : "메모가 없습니다",
                    systemImage: selection == .trash ? "trash" : "note.text"
                )
            }
        }
    }

    private var searchResultsList: some View {
        List(selection: $viewModel.selectedNoteID) {
            ForEach(viewModel.searchResults) { hit in
                searchRow(for: hit).tag(hit.noteID)
            }
        }
        .listStyle(.inset)
        .overlay {
            if viewModel.searchResults.isEmpty {
                ContentUnavailableView.search(text: viewModel.searchQuery)
            }
        }
    }

    private var filterMenu: some View {
        Menu {
            Toggle("즐겨찾기만", isOn: Binding(
                get: { viewModel.searchFilters.favoritesOnly },
                set: { viewModel.searchFilters.favoritesOnly = $0 }
            ))

            Menu("태그") {
                Button("전체") { viewModel.searchFilters.tagID = nil }
                ForEach(availableTags) { tag in
                    Button(tag.name) { viewModel.searchFilters.tagID = tag.id }
                }
            }

            Menu("수정일") {
                Button("전체") { viewModel.searchFilters.updatedAfter = nil }
                Button("오늘") { viewModel.searchFilters.updatedAfter = Calendar.current.startOfDay(for: Date()) }
                Button("최근 7일") { viewModel.searchFilters.updatedAfter = Calendar.current.date(byAdding: .day, value: -7, to: Date()) }
                Button("최근 30일") { viewModel.searchFilters.updatedAfter = Calendar.current.date(byAdding: .day, value: -30, to: Date()) }
            }
        } label: {
            Image(systemName: viewModel.searchFilters.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
        .help("검색 필터")
        .accessibilityLabel(viewModel.searchFilters.isEmpty ? "검색 필터" : "검색 필터 적용됨")
    }

    @ViewBuilder
    private func row(for note: Note) -> some View {
        let isChecked = viewModel.checkedNoteIDs.contains(note.id)
        let content = HStack(alignment: .top, spacing: 8) {
            if viewModel.isSelecting {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isChecked ? Color.accentColor : Color.secondary)
                    .font(.system(size: 16))
                    .padding(.top, 2)
                    .accessibilityLabel(isChecked ? "선택됨" : "선택 안 됨")
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(note.displayTitle)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    if note.isFavorite {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .font(.caption)
                    }
                }
                Text(note.previewText.isEmpty ? "추가 텍스트 없음" : note.previewText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack {
                    Text(Self.dateFormatter.string(from: note.updatedAt))
                    if selection == .trash, let deletedAt = note.deletedAt {
                        Text("· \(daysUntilPurge(deletedAt))일 후 자동 삭제")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onDrag { dragPayload(for: note).makeItemProvider() }

        if viewModel.isSelecting {
            content.onTapGesture { viewModel.toggleChecked(note.id) }
        } else {
            // List(selection:)의 기본 클릭-선택 동작이 .onDrag(드래그 앤 드롭 소스)와 같은 행에
            // 있으면 macOS에서 이따금 씹힌다 — 클릭해도 선택(=편집기에 열림)이 안 되던 원인이라,
            // 명시적으로 선택을 지정해서 List의 암묵적 처리에 기대지 않게 한다.
            content
                .onTapGesture { viewModel.selectedNoteID = note.id }
                .contextMenu {
                    if selection == .trash {
                        Button("복원") { Task { await viewModel.restore(note) } }
                        Button("지금 완전히 삭제", role: .destructive) {
                            Task { await viewModel.deletePermanently(note) }
                        }
                    } else {
                        Button(note.isFavorite ? "즐겨찾기 해제" : "즐겨찾기 추가") {
                            Task { await viewModel.toggleFavorite(note) }
                        }
                        Button("휴지통으로 이동", role: .destructive) {
                            Task { await viewModel.moveToTrash(note) }
                        }
                    }
                }
        }
    }

    @ViewBuilder
    private func searchRow(for hit: SearchHit) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(hit.title)
                .font(.headline)
                .lineLimit(1)
            Text(SearchSnippetBuilder.makeSnippet(from: hit.snippet, query: viewModel.searchQuery))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Text(Self.dateFormatter.string(from: hit.updatedAt))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { viewModel.selectedNoteID = hit.noteID }
        .onDrag { NoteDragPayload(noteIDs: [hit.noteID]).makeItemProvider() }
    }

    /// 체크상자 선택 모드에서 이미 여러 개가 체크된 행을 끌면 체크된 것 전부를, 그 외에는
    /// 지금 끌기 시작한 행 하나만 옮긴다.
    private func dragPayload(for note: Note) -> NoteDragPayload {
        if viewModel.isSelecting, viewModel.checkedNoteIDs.contains(note.id), viewModel.checkedNoteIDs.count > 1 {
            return NoteDragPayload(noteIDs: Array(viewModel.checkedNoteIDs))
        }
        return NoteDragPayload(noteIDs: [note.id])
    }

    private func daysUntilPurge(_ deletedAt: Date) -> Int {
        let expiry = Calendar.current.date(byAdding: .day, value: 30, to: deletedAt) ?? deletedAt
        let days = Calendar.current.dateComponents([.day], from: Date(), to: expiry).day ?? 0
        return max(0, days)
    }
}
