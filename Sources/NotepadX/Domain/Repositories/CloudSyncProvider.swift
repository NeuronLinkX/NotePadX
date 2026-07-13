import Foundation

/// 스펙 13.2절. Finder 동기화 폴더(OneDriveFolderSyncProvider)와 Microsoft Graph
/// (MicrosoftGraphSyncProvider) 둘 다 이 인터페이스를 구현해, 상위 UseCase는
/// 어떤 백엔드로 동기화하는지 몰라도 되게 한다.
protocol CloudSyncProvider: Sendable {
    func authenticate() async throws
    func signOut() async throws
    func listNotes() async throws -> [RemoteNote]
    func upload(_ note: SyncDocument) async throws
    func download(id: String) async throws -> SyncDocument
    func delete(id: String) async throws
}
