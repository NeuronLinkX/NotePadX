import Foundation

@MainActor
final class SidebarViewModel: ObservableObject {
    @Published var folders: [Folder] = []
    @Published var tags: [Tag] = []
    @Published var selection: SidebarSelection = .all
    @Published var errorMessage: String?

    private let folderUseCase: FolderUseCase
    private let tagUseCase: TagUseCase

    init(folderUseCase: FolderUseCase, tagUseCase: TagUseCase) {
        self.folderUseCase = folderUseCase
        self.tagUseCase = tagUseCase
    }

    func load() async {
        do {
            async let foldersTask = folderUseCase.fetchAllFolders()
            async let tagsTask = tagUseCase.fetchAllTags()
            folders = try await foldersTask
            tags = try await tagsTask
        } catch {
            report(error)
        }
    }

    /// 편집기 안에서 노트에 태그를 붙이거나 새 태그를 만들었을 때 ContentView가 호출한다.
    /// `load()`와 달리 폴더는 다시 불러오지 않아 더 가볍다.
    func refreshTags() async {
        do {
            tags = try await tagUseCase.fetchAllTags()
        } catch {
            report(error)
        }
    }

    func createFolder(name: String, parentID: UUID?) async {
        do {
            _ = try await folderUseCase.createFolder(name: name, parentID: parentID)
            await load()
        } catch {
            report(error)
        }
    }

    func rename(id: UUID, to newName: String) async {
        do {
            try await folderUseCase.rename(id: id, to: newName)
            await load()
        } catch {
            report(error)
        }
    }

    func delete(id: UUID) async {
        do {
            try await folderUseCase.delete(id: id)
            if selection == .folder(id) { selection = .all }
            await load()
        } catch {
            report(error)
        }
    }

    func childFolders(of parentID: UUID?) -> [Folder] {
        folders.filter { $0.parentID == parentID }.sorted { $0.sortIndex < $1.sortIndex }
    }

    /// 평면 목록을 OutlineGroup에 바로 넘길 수 있는 트리로 변환한다.
    func folderTree() -> [FolderTreeNode] {
        func build(parentID: UUID?) -> [FolderTreeNode] {
            childFolders(of: parentID).map { FolderTreeNode(folder: $0, children: build(parentID: $0.id)) }
        }
        return build(parentID: nil)
    }

    func createTag(name: String) async {
        do {
            _ = try await tagUseCase.createTag(name: name)
            await load()
        } catch {
            report(error)
        }
    }

    func renameTag(id: UUID, to newName: String) async {
        do {
            try await tagUseCase.rename(id: id, to: newName)
            await load()
        } catch {
            report(error)
        }
    }

    func deleteTag(id: UUID) async {
        do {
            try await tagUseCase.delete(id: id)
            if selection == .tag(id) { selection = .all }
            await load()
        } catch {
            report(error)
        }
    }

    private func report(_ error: Error) {
        errorMessage = (error as? AppError)?.errorDescription ?? error.localizedDescription
    }
}

struct FolderTreeNode: Identifiable {
    let folder: Folder
    var children: [FolderTreeNode]
    var id: UUID { folder.id }
    /// children이 비어 있으면 nil을 돌려줘야 OutlineGroup이 펼침 화살표를 그리지 않는다.
    var childrenOrNil: [FolderTreeNode]? { children.isEmpty ? nil : children }
}
