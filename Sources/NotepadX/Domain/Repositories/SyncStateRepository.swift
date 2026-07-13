import Foundation

struct NoteSyncState: Sendable, Equatable {
    var noteID: UUID
    var lastSyncedContentHash: String?
    var lastSyncedUpdatedAt: Date?
    var lastSyncedAt: Date
    var remoteDeviceID: String?
}

protocol SyncStateRepository: Sendable {
    func syncState(forNote noteID: UUID) async throws -> NoteSyncState?
    func setSyncState(_ state: NoteSyncState) async throws
    func removeSyncState(forNote noteID: UUID) async throws
}
