import Foundation

struct SQLiteNoteRevisionRepository: NoteRevisionRepository {
    private let db: DatabaseManager

    init(db: DatabaseManager) {
        self.db = db
    }

    private func mapRow(_ row: StatementRow) throws -> NoteRevision {
        guard let idString = row.string(0), let id = UUID(uuidString: idString),
              let noteIDString = row.string(1), let noteID = UUID(uuidString: noteIDString) else {
            throw AppError.documentCorrupted
        }
        let reason = NoteRevisionReason(rawValue: row.string(4) ?? "") ?? .periodicEdit
        return NoteRevision(
            id: id,
            noteID: noteID,
            documentJSON: row.blob(2) ?? Data(),
            plainText: row.string(3) ?? "",
            reason: reason,
            createdAt: row.date(5) ?? Date()
        )
    }

    func createRevision(_ revision: NoteRevision) async throws {
        try await db.execute(
            """
            INSERT INTO note_revision (id, note_id, document_json, plain_text, reason, created_at)
            VALUES (?, ?, ?, ?, ?, ?);
            """,
            [
                .text(revision.id.uuidString),
                .text(revision.noteID.uuidString),
                .blob(revision.documentJSON),
                .text(revision.plainText),
                .text(revision.reason.rawValue),
                .double(revision.createdAt.timeIntervalSince1970),
            ]
        )
    }

    func revisions(forNote noteID: UUID) async throws -> [NoteRevision] {
        try await db.query(
            """
            SELECT id, note_id, document_json, plain_text, reason, created_at
            FROM note_revision WHERE note_id = ? ORDER BY created_at DESC;
            """,
            [.text(noteID.uuidString)],
            map: mapRow
        )
    }

    func revision(id: UUID) async throws -> NoteRevision? {
        try await db.query(
            "SELECT id, note_id, document_json, plain_text, reason, created_at FROM note_revision WHERE id = ? LIMIT 1;",
            [.text(id.uuidString)],
            map: mapRow
        ).first
    }

    func pruneOldRevisions(noteID: UUID, keep: Int) async throws {
        try await db.execute(
            """
            DELETE FROM note_revision WHERE note_id = ? AND id NOT IN (
                SELECT id FROM note_revision WHERE note_id = ? ORDER BY created_at DESC LIMIT ?
            );
            """,
            [.text(noteID.uuidString), .text(noteID.uuidString), .int(Int64(keep))]
        )
    }
}
