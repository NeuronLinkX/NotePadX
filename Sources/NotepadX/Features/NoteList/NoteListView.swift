import SwiftUI

struct NoteListView: View {
    @ObservedObject var viewModel: NoteListViewModel
    let selection: SidebarSelection
    let currentFolderID: UUID?
    let availableTags: [Tag]

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
        .navigationTitle(viewModel.isSearching ? "검색 결과" : selection.title)
        .searchable(text: $viewModel.searchQuery, placement: .toolbar, prompt: "제목, 본문, 코드, 태그 검색")
        .toolbar {
            ToolbarItem {
                filterMenu
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
        .task(id: selection) {
            await viewModel.load(filter: selection.noteListFilter)
        }
        .onChange(of: viewModel.searchQuery) { _, _ in viewModel.performSearch() }
        .onChange(of: viewModel.searchFilters) { _, _ in viewModel.performSearch() }
        .alert("오류", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var noteList: some View {
        List(selection: $viewModel.selectedNoteID) {
            ForEach(viewModel.notes) { note in
                row(for: note).tag(note.id)
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
        .padding(.vertical, 4)
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
    }

    private func daysUntilPurge(_ deletedAt: Date) -> Int {
        let expiry = Calendar.current.date(byAdding: .day, value: 30, to: deletedAt) ?? deletedAt
        let days = Calendar.current.dateComponents([.day], from: Date(), to: expiry).day ?? 0
        return max(0, days)
    }
}
