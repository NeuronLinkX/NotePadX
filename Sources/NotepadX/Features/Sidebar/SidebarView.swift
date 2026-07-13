import SwiftUI

struct SidebarView: View {
    @ObservedObject var viewModel: SidebarViewModel
    @ObservedObject var oneDriveViewModel: OneDriveViewModel
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
