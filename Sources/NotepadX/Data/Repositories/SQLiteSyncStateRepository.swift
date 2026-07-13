import Foundation

struct SQLiteSyncStateRepository: SyncStateRepository {
    private let db: DatabaseManager

    init(db: DatabaseManager) {
        self.db = db
    }

    private func mapRow(_ row: StatementRow) throws -> NoteSyncState {
        guard let idString = row.string(0), let id = UUID(uuidString: idString) else {
            throw AppError.documentCorrupted
        }
        return NoteSyncState(
            noteID: id,
            lastSyncedContentHash: row.string(1),
            lastSyncedUpdatedAt: row.date(2),
            lastSyncedAt: row.date(3) ?? Date(),
            remoteDeviceID: row.string(4)
        )
    }

    func syncState(forNote noteID: UUID) async throws -> NoteSyncState? {
        try await db.query(
            """
            SELECT note_id, last_synced_content_hash, last_synced_updated_at, last_synced_at, remote_device_id
            FROM note_sync_state WHERE note_id = ? LIMIT 1;
            """,
            [.text(noteID.uuidString)],
            map: mapRow
        ).first
    }

    func setSyncState(_ state: NoteSyncState) async throws {
        try await db.execute(
            """
            INSERT INTO note_sync_state (note_id, last_synced_content_hash, last_synced_updated_at, last_synced_at, remote_device_id)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(note_id) DO UPDATE SET
                last_synced_content_hash = excluded.last_synced_content_hash,
                last_synced_updated_at = excluded.last_synced_updated_at,
                last_synced_at = excluded.last_synced_at,
                remote_device_id = excluded.remote_device_id;
            """,
            [
                .text(state.noteID.uuidString),
                state.lastSyncedContentHash.map { .text($0) } ?? .null,
                state.lastSyncedUpdatedAt.map { .double($0.timeIntervalSince1970) } ?? .null,
                .double(state.lastSyncedAt.timeIntervalSince1970),
                state.remoteDeviceID.map { .text($0) } ?? .null,
            ]
        )
    }

    func removeSyncState(forNote noteID: UUID) async throws {
        try await db.execute("DELETE FROM note_sync_state WHERE note_id = ?;", [.text(noteID.uuidString)])
    }
}
