import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// macOS Notes 스타일 3열 레이아웃 (스펙 4절): 사이드바 / 노트 목록 / 편집기.
/// 편집기 영역 자체는 분할 편집(스펙 9절)을 지원하는 WorkspaceViewModel이 관리한다.
struct ContentView: View {
    @StateObject private var sidebarViewModel: SidebarViewModel
    @StateObject private var noteListViewModel: NoteListViewModel
    @StateObject private var workspace: WorkspaceViewModel
    @StateObject private var openTabs: OpenTabsViewModel
    @StateObject private var noteGraphViewModel: NoteGraphViewModel
    @ObservedObject private var oneDriveViewModel: OneDriveViewModel
    @State private var standalonePDFURL: URL?

    init(environment: AppEnvironment) {
        let sidebar = SidebarViewModel(
            folderUseCase: environment.folderUseCase,
            tagUseCase: environment.tagUseCase
        )
        let noteList = NoteListViewModel(
            noteUseCase: environment.noteUseCase,
            tagUseCase: environment.tagUseCase,
            searchUseCase: environment.searchUseCase
        )
        let workspaceViewModel = WorkspaceViewModel(
            noteUseCase: environment.noteUseCase,
            tagUseCase: environment.tagUseCase,
            revisionUseCase: environment.revisionUseCase
        )
        let tabs = OpenTabsViewModel(noteUseCase: environment.noteUseCase)
        let noteGraph = NoteGraphViewModel(noteUseCase: environment.noteUseCase)
        // 편집기에서 저장이 성공하면: 1) 노트 목록의 제목/미리보기를 즉시 갱신하고
        // 2) OneDrive 폴더가 설정되어 있으면 그 노트를 자동으로 동기화한다 — 폴더를 한 번
        // 고르고 나면 그 뒤로는 "지금 동기화"를 매번 누르지 않아도 되게 하기 위함이다.
        let oneDrive = environment.oneDriveViewModel
        let onSaved: (Note) -> Void = { [weak noteList, weak tabs] note in
            noteList?.applyExternalUpdate(note)
            tabs?.updateTitle(note.id, title: note.displayTitle)
            Task { await oneDrive.syncNoteIfConfigured(note.id) }
        }
        // 편집기 안에서 태그를 붙이거나 새로 만들면, 또는 노트를 영구 삭제해서 태그가 자동
        // 정리되면 사이드바의 "태그" 목록도 바로 갱신한다 — 이 콜백이 없으면 사이드바는 다음
        // 전체 재조회 전까지 그 변화를 보여주지 않는다.
        let onTagsChanged: () -> Void = { [weak sidebar] in
            Task { await sidebar?.refreshTags() }
        }
        workspaceViewModel.primaryEditor.onNoteUpdated = onSaved
        workspaceViewModel.secondaryEditor.onNoteUpdated = onSaved
        workspaceViewModel.primaryEditor.onTagsChanged = onTagsChanged
        workspaceViewModel.secondaryEditor.onTagsChanged = onTagsChanged
        noteList.onTagsChanged = onTagsChanged

        _sidebarViewModel = StateObject(wrappedValue: sidebar)
        _noteListViewModel = StateObject(wrappedValue: noteList)
        _workspace = StateObject(wrappedValue: workspaceViewModel)
        _openTabs = StateObject(wrappedValue: tabs)
        _noteGraphViewModel = StateObject(wrappedValue: noteGraph)
        _oneDriveViewModel = ObservedObject(wrappedValue: environment.oneDriveViewModel)
    }

    private var currentFolderID: UUID? {
        if case .folder(let id) = sidebarViewModel.selection { return id }
        return nil
    }

    private var searchHighlightQuery: String? {
        noteListViewModel.isSearching ? noteListViewModel.searchQuery : nil
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(
                viewModel: sidebarViewModel,
                oneDriveViewModel: oneDriveViewModel,
                onDropNotesOnFolder: { ids, folderID in
                    Task { await noteListViewModel.moveNotes(ids, toFolderID: folderID) }
                }
            )
                .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } content: {
            NoteListView(
                viewModel: noteListViewModel,
                selection: sidebarViewModel.selection,
                currentFolderID: currentFolderID,
                availableFolders: sidebarViewModel.folders,
                availableTags: sidebarViewModel.tags
            )
            .navigationSplitViewColumnWidth(min: 240, ideal: 300)
        } detail: {
            VStack(spacing: 0) {
                EditorTabBarView(tabsViewModel: openTabs, activeNoteID: $noteListViewModel.selectedNoteID)
                Divider()
                editorArea
            }
        }
        .focusedSceneValue(\.newNoteAction) {
            Task { await noteListViewModel.createNote(folderID: currentFolderID) }
        }
        .focusedSceneValue(\.newFolderAction) {
            Task { await sidebarViewModel.createFolder(name: "새 폴더", parentID: currentFolderID) }
        }
        .focusedSceneValue(\.saveAction) {
            Task {
                await workspace.primaryEditor.flush()
                if workspace.splitMode.isSplit { await workspace.secondaryEditor.flush() }
            }
        }
        .focusedSceneValue(\.toggleHorizontalSplitAction) {
            workspace.toggleHorizontalSplit(primaryNoteID: noteListViewModel.selectedNoteID)
        }
        .focusedSceneValue(\.toggleVerticalSplitAction) {
            workspace.toggleVerticalSplit(primaryNoteID: noteListViewModel.selectedNoteID)
        }
        .focusedSceneValue(\.newTabAction) {
            Task { await noteListViewModel.createNote(folderID: currentFolderID) }
        }
        .focusedSceneValue(\.closeTabAction, noteListViewModel.selectedNoteID != nil ? {
            if let id = noteListViewModel.selectedNoteID {
                noteListViewModel.selectedNoteID = openTabs.closeTab(id, activeNoteID: id)
            }
        } : nil)
        .focusedSceneValue(\.openPDFAction) { presentPDFOpenPanel() }
        .onChange(of: sidebarViewModel.selection) { _, _ in
            noteListViewModel.selectedNoteID = nil
        }
        .onChange(of: noteListViewModel.selectedNoteID, initial: true) { _, newValue in
            let knownTitle = noteListViewModel.notes.first(where: { $0.id == newValue })?.displayTitle
                ?? noteListViewModel.searchResults.first(where: { $0.noteID == newValue })?.title
            openTabs.noteOpened(newValue, knownTitle: knownTitle)
        }
        .sheet(isPresented: Binding(
            get: { standalonePDFURL != nil },
            set: { if !$0 { standalonePDFURL = nil } }
        )) {
            if let url = standalonePDFURL {
                PDFPreviewSheet(url: url, onClose: { standalonePDFURL = nil })
            }
        }
    }

    /// File > Open PDF… (스펙: Office Viewer). 노트에 첨부하지 않고도 디스크의 임의 PDF를 바로 본다.
    private func presentPDFOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        standalonePDFURL = url
    }

    @ViewBuilder
    private var editorArea: some View {
        switch workspace.splitMode {
        case .none:
            EditorView(
                viewModel: workspace.primaryEditor,
                noteID: $noteListViewModel.selectedNoteID,
                availableTags: sidebarViewModel.tags,
                searchHighlightQuery: searchHighlightQuery,
                noteGraphViewModel: noteGraphViewModel
            )
        case .horizontal, .vertical:
            ResizableSplitView(
                axis: workspace.splitMode.axis,
                ratio: Binding(get: { workspace.splitRatio }, set: { workspace.setSplitRatio($0) })
            ) {
                EditorView(
                    viewModel: workspace.primaryEditor,
                    noteID: $noteListViewModel.selectedNoteID,
                    availableTags: sidebarViewModel.tags,
                    notePickerOptions: noteListViewModel.notes,
                    onClosePane: { workspace.closeSplit() },
                    searchHighlightQuery: searchHighlightQuery,
                    noteGraphViewModel: noteGraphViewModel
                )
            } second: {
                EditorView(
                    viewModel: workspace.secondaryEditor,
                    noteID: $workspace.secondaryNoteID,
                    availableTags: sidebarViewModel.tags,
                    notePickerOptions: noteListViewModel.notes,
                    onClosePane: { workspace.closeSplit() }
                )
            }
        }
    }
}
