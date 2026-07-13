import Foundation

protocol FolderRepository: Sendable {
    func fetchAllFolders() async throws -> [Folder]
    func createFolder(_ folder: Folder) async throws
    func renameFolder(id: UUID, newName: String) async throws
    func moveFolder(id: UUID, newParentID: UUID?) async throws
    func deleteFolder(id: UUID) async throws
    func noteCount(folderID: UUID) async throws -> Int
}
