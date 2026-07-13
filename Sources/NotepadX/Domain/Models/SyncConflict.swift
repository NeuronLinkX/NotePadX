import Foundation

/// 로컬과 원격이 마지막 동기화 이후 둘 다 바뀌어서 자동으로 병합할 수 없는 상태 (스펙 13절).
/// 절대 한쪽을 조용히 덮어쓰지 않고, 사용자가 아래 중 하나를 선택하게 한다.
struct SyncConflict: Identifiable, Sendable, Equatable {
    var noteID: UUID
    var localTitle: String
    var localPlainText: String
    var localUpdatedAt: Date
    var remoteTitle: String
    var remotePlainText: String
    var remoteUpdatedAt: Date

    var id: UUID { noteID }
}

enum SyncConflictResolution: Sendable, Equatable {
    case keepLocal
    case keepRemote
    /// 둘 다 보존한다 — 원격 버전을 새 노트로 복제해 두고 로컬은 그대로 둔다.
    case keepBoth
}

/// 노트 하나의 동기화 결과.
enum SyncOutcome: Sendable, Equatable {
    case upToDate
    case uploaded
    case downloaded
    case conflict(SyncConflict)
}
