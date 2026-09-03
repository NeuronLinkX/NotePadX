import SwiftUI

/// macOS Notes 스타일 3열 레이아웃 (스펙 4절): 사이드바 / 노트 목록 / 편집기.
/// 편집기 영역 자체는 분할 편집(스펙 9절)을 지원하는 WorkspaceViewModel이 관리한다.
struct ContentView: View {
    @StateObject private var sidebarViewModel: SidebarViewModel
    @StateObject private var noteListViewModel: NoteListViewModel
    @StateObject private var workspace: WorkspaceViewModel
    @ObservedObject private var oneDriveViewModel: OneDriveViewModel

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
        // 편집기에서 저장이 성공하면: 1) 노트 목록의 제목/미리보기를 즉시 갱신하고
        // 2) OneDrive 폴더가 설정되어 있으면 그 노트를 자동으로 동기화한다 — 폴더를 한 번
        // 고르고 나면 그 뒤로는 "지금 동기화"를 매번 누르지 않아도 되게 하기 위함이다.
        let oneDrive = environment.oneDriveViewModel
        let onSaved: (Note) -> Void = { [weak noteList] note in
            noteList?.applyExternalUpdate(note)
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
        _oneDriveViewModel = ObservedObject(wrappedValue: environment.oneDriveViewModel)
    }

    private var currentFolderID: UUID? {
        if case .folder(let id) = sidebarViewModel.selection { return id }
        return nil
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
            editorArea
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
        .onChange(of: sidebarViewModel.selection) { _, _ in
            noteListViewModel.selectedNoteID = nil
        }
    }

    @ViewBuilder
    private var editorArea: some View {
        switch workspace.splitMode {
        case .none:
            EditorView(
                viewModel: workspace.primaryEditor,
                noteID: $noteListViewModel.selectedNoteID,
                availableTags: sidebarViewModel.tags
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
                    onClosePane: { workspace.closeSplit() }
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
