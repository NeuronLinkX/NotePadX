import Foundation

/// 로컬 저장소(SQLite)와 동기화 대상(OneDrive 폴더 또는 Microsoft Graph) 사이를 오가는
/// 노트의 전송 표현. Note 전체가 아니라 동기화에 필요한 필드만 담는다.
struct SyncDocument: Codable, Sendable, Equatable {
    var noteID: UUID
    var title: String
    var documentJSON: Data
    var plainText: String
    var updatedAt: Date
    var contentHash: String
    /// 이 문서가 마지막으로 동기화됐을 때의 콘텐츠 해시. 3-way 충돌 감지의 기준값(base)이다.
    var baseRevision: String?
    var deviceID: String
}

/// CloudSyncProvider.listNotes()가 돌려주는, 원격에 있는 노트의 가벼운 메타데이터.
struct RemoteNote: Codable, Sendable, Equatable {
    var id: String
    var title: String
    var updatedAt: Date
    var contentHash: String
}
