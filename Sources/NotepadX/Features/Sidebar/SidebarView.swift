import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @ObservedObject var viewModel: SidebarViewModel
    @ObservedObject var oneDriveViewModel: OneDriveViewModel
    /// 메모 목록에서 폴더 행으로 노트를 끌어다 놓았을 때 ContentView가 실제 이동을 수행한다 —
    /// SidebarViewModel은 폴더/태그만 알고 NoteUseCase는 모르므로, 이동 자체는 여기서 하지 않는다.
    var onDropNotesOnFolder: (Set<UUID>, UUID) -> Void = { _, _ in }
    @State private var dropTargetFolderID: UUID?
    @State private var isShowingNewFolderPrompt = false
    @State private var newFolderName = ""
    @State private var renamingFolderID: UUID?
    @State private var renameText = ""

    @State private var isShowingNewTagPrompt = false
    @State private var newTagName = ""
    @State private var renamingTagID: UUID?
    @State private var renameTagText = ""

    @State private var isShowingOneDriveSettings = false

    var body: some View {
        List(selection: $viewModel.selection) {
            Section("라이브러리") {
                Label("모든 메모", systemImage: "note.text").tag(SidebarSelection.all)
                Label("최근 메모", systemImage: "clock").tag(SidebarSelection.recent)
                Label("즐겨찾기", systemImage: "star").tag(SidebarSelection.favorites)
                Label("휴지통", systemImage: "trash").tag(SidebarSelection.trash)
            }

            Section("폴더") {
                OutlineGroup(viewModel.folderTree(), children: \.childrenOrNil) { node in
                    folderRow(node.folder)
                }
            }

            Section("태그") {
                ForEach(viewModel.tags) { tag in
                    tagRow(tag)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(AppConfig.displayName)
        .toolbar {
            ToolbarItem {
                Menu {
                    Button {
                        newFolderName = ""
                        isShowingNewFolderPrompt = true
                    } label: {
                        Label("새 폴더", systemImage: "folder.badge.plus")
                    }
                    Button {
                        newTagName = ""
                        isShowingNewTagPrompt = true
                    } label: {
                        Label("새 태그", systemImage: "tag")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .help("새로 만들기")
                .accessibilityLabel("새로 만들기")
            }
            ToolbarItem {
                Button { isShowingOneDriveSettings = true } label: {
                    Image(systemName: "icloud")
                }
                .help("OneDrive 동기화…")
                .accessibilityLabel("OneDrive 동기화")
            }
        }
        .sheet(isPresented: $isShowingOneDriveSettings) {
            OneDriveSettingsView(viewModel: oneDriveViewModel)
        }
        .alert("새 폴더", isPresented: $isShowingNewFolderPrompt) {
            TextField("폴더 이름", text: $newFolderName)
            Button("취소", role: .cancel) {}
            Button("만들기") {
                let parentID: UUID? = { if case .folder(let id) = viewModel.selection { return id } else { return nil } }()
                Task { await viewModel.createFolder(name: newFolderName, parentID: parentID) }
            }
        }
        .alert("폴더 이름 변경", isPresented: Binding(
            get: { renamingFolderID != nil },
            set: { if !$0 { renamingFolderID = nil } }
        )) {
            TextField("폴더 이름", text: $renameText)
            Button("취소", role: .cancel) {}
            Button("변경") {
                if let id = renamingFolderID {
                    Task { await viewModel.rename(id: id, to: renameText) }
                }
            }
        }
        .alert("새 태그", isPresented: $isShowingNewTagPrompt) {
            TextField("태그 이름", text: $newTagName)
            Button("취소", role: .cancel) {}
            Button("만들기") {
                Task { await viewModel.createTag(name: newTagName) }
            }
        }
        .alert("태그 이름 변경", isPresented: Binding(
            get: { renamingTagID != nil },
            set: { if !$0 { renamingTagID = nil } }
        )) {
            TextField("태그 이름", text: $renameTagText)
            Button("취소", role: .cancel) {}
            Button("변경") {
                if let id = renamingTagID {
                    Task { await viewModel.renameTag(id: id, to: renameTagText) }
                }
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
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private func folderRow(_ folder: Folder) -> some View {
        Label(folder.name, systemImage: folder.iconSystemName)
            // Label 혼자서는 아이콘+글자 너비만큼만 히트테스트 영역을 갖는다 — List가 선택
            // 하이라이트는 행 전체로 넓혀 보여줘도, 우리가 붙이는 dropDestination의 감지
            // 영역은 이 뷰의 실제 레이아웃 프레임을 그대로 따른다. 그래서 드롭 대상이 사실상
            // 글자 위에만 좁게 반응하고 행의 나머지 빈 공간에서는 반응하지 않았다 — 행 전체
            // 너비로 넓히고 그 사각형을 히트테스트 모양으로 명시해야 실제로 어디에 놓아도 먹힌다.
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .tag(SidebarSelection.folder(folder.id))
            .contextMenu {
                Button("이름 변경") {
                    renamingFolderID = folder.id
                    renameText = folder.name
                }
                Button("삭제", role: .destructive) {
                    Task { await viewModel.delete(id: folder.id) }
                }
            }
            .listRowBackground(dropTargetFolderID == folder.id ? Color.accentColor.opacity(0.18) : nil)
            .onDrop(of: [UTType.notepadXNoteIDs], isTargeted: Binding(
                get: { dropTargetFolderID == folder.id },
                set: { isTargeted in
                    // 드래그가 한 폴더 행에서 다른 행으로 넘어갈 때 두 콜백의 도착 순서가
                    // 보장되지 않으므로, "떠났다"는 이 행이 여전히 표시 중일 때만 지운다 —
                    // 그래야 새 행이 먼저 켜진 뒤 옛 행이 늦게 꺼지면서 새 강조를 지우는 일이 없다.
                    dropTargetFolderID = isTargeted ? folder.id : (dropTargetFolderID == folder.id ? nil : dropTargetFolderID)
                }
            )) { providers in
                NoteDragPayload.loadAll(from: providers) { ids in
                    onDropNotesOnFolder(ids, folder.id)
                }
                return true
            }
    }

    @ViewBuilder
    private func tagRow(_ tag: Tag) -> some View {
        Label(tag.name, systemImage: "tag")
            .tag(SidebarSelection.tag(tag.id))
            .contextMenu {
                Button("이름 변경") {
                    renamingTagID = tag.id
                    renameTagText = tag.name
                }
                Button("삭제", role: .destructive) {
                    Task { await viewModel.deleteTag(id: tag.id) }
                }
            }
    }
}
