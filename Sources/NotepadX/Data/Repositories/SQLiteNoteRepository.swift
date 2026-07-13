import Foundation

struct SQLiteNoteRepository: NoteRepository {
    private let db: DatabaseManager

    init(db: DatabaseManager) {
        self.db = db
    }

    private static let selectColumns = """
        id, folder_id, title, document_json, plain_text, created_at, updated_at, \
        deleted_at, is_favorite, is_pinned, source, content_hash, sync_state
        """

    private func mapRow(_ row: StatementRow) throws -> Note {
        guard let idString = row.string(0), let id = UUID(uuidString: idString) else {
            throw AppError.documentCorrupted
        }
        let folderID = row.string(1).flatMap(UUID.init(uuidString:))
        let title = row.string(2) ?? ""
        let documentJSON = row.blob(3) ?? Data()
        let plainText = row.string(4) ?? ""
        let createdAt = row.date(5) ?? Date()
        let updatedAt = row.date(6) ?? Date()
        let deletedAt = row.date(7)
        let isFavorite = row.bool(8) ?? false
        let isPinned = row.bool(9) ?? false
        let source = NoteSource(rawValue: row.string(10) ?? "") ?? .local
        let contentHash = row.string(11) ?? ""
        let syncState = SyncState(rawValue: row.string(12) ?? "") ?? .notSynced

        return Note(
            id: id,
            folderID: folderID,
            title: title,
            documentJSON: documentJSON,
            plainText: plainText,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            isFavorite: isFavorite,
            isPinned: isPinned,
            source: source,
            contentHash: contentHash,
            syncState: syncState
        )
    }

    private func bindings(for note: Note) -> [DatabaseValue] {
        [
            .text(note.id.uuidString),
            note.folderID.map { .text($0.uuidString) } ?? .null,
            .text(note.title),
            .blob(note.documentJSON),
            .text(note.plainText),
            .double(note.createdAt.timeIntervalSince1970),
            .double(note.updatedAt.timeIntervalSince1970),
            note.deletedAt.map { .double($0.timeIntervalSince1970) } ?? .null,
            .int(note.isFavorite ? 1 : 0),
            .int(note.isPinned ? 1 : 0),
            .text(note.source.rawValue),
            .text(note.contentHash),
            .text(note.syncState.rawValue),
        ]
    }

    func fetchNotes(filter: NoteListFilter, sortOrder: NoteSortOrder) async throws -> [Note] {
        var fromClause = "note"
        var whereClause: String
        var bindings: [DatabaseValue] = []

        switch filter {
        case .all:
            whereClause = "deleted_at IS NULL"
        case .folder(let folderID):
            whereClause = "deleted_at IS NULL AND folder_id = ?"
            bindings = [.text(folderID.uuidString)]
        case .favorites:
            whereClause = "deleted_at IS NULL AND is_favorite = 1"
        case .trash:
            whereClause = "deleted_at IS NOT NULL"
        case .recent:
            whereClause = "deleted_at IS NULL"
        case .tag(let tagID):
            fromClause = "note JOIN note_tag ON note_tag.note_id = note.id"
            whereClause = "deleted_at IS NULL AND note_tag.tag_id = ?"
            bindings = [.text(tagID.uuidString)]
        }

        let orderClause: String
        switch sortOrder {
        case .updatedDescending: orderClause = "updated_at DESC"
        case .createdDescending: orderClause = "created_at DESC"
        case .titleAscending: orderClause = "title COLLATE NOCASE ASC"
        }

        let limitClause = filter == .recent ? "LIMIT 50" : ""
        let sql = "SELECT \(Self.selectColumns) FROM \(fromClause) WHERE \(whereClause) ORDER BY is_pinned DESC, \(orderClause) \(limitClause);"
        return try await db.query(sql, bindings, map: mapRow)
    }

    func fetchNote(id: UUID) async throws -> Note? {
        let sql = "SELECT \(Self.selectColumns) FROM note WHERE id = ? LIMIT 1;"
        return try await db.query(sql, [.text(id.uuidString)], map: mapRow).first
    }

    func createNote(_ note: Note) async throws {
        let sql = """
            INSERT INTO note (\(Self.selectColumns)) \
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
        try await db.execute(sql, bindings(for: note))
    }

    func updateNote(_ note: Note) async throws {
        let sql = """
            UPDATE note SET folder_id = ?, title = ?, document_json = ?, plain_text = ?, \
            updated_at = ?, deleted_at = ?, is_favorite = ?, is_pinned = ?, source = ?, \
            content_hash = ?, sync_state = ? WHERE id = ?;
            """
        let params: [DatabaseValue] = [
            note.folderID.map { .text($0.uuidString) } ?? .null,
            .text(note.title),
            .blob(note.documentJSON),
            .text(note.plainText),
            .double(note.updatedAt.timeIntervalSince1970),
            note.deletedAt.map { .double($0.timeIntervalSince1970) } ?? .null,
            .int(note.isFavorite ? 1 : 0),
            .int(note.isPinned ? 1 : 0),
            .text(note.source.rawValue),
            .text(note.contentHash),
            .text(note.syncState.rawValue),
            .text(note.id.uuidString),
        ]
        try await db.execute(sql, params)
    }

    func updateNoteIfUnchanged(_ note: Note, expectedUpdatedAt: Date) async throws -> Bool {
        let sql = """
            UPDATE note SET folder_id = ?, title = ?, document_json = ?, plain_text = ?, \
            updated_at = ?, deleted_at = ?, is_favorite = ?, is_pinned = ?, source = ?, \
            content_hash = ?, sync_state = ? WHERE id = ? AND updated_at = ?;
            """
        let params: [DatabaseValue] = [
            note.folderID.map { .text($0.uuidString) } ?? .null,
            .text(note.title),
            .blob(note.documentJSON),
            .text(note.plainText),
            .double(note.updatedAt.timeIntervalSince1970),
            note.deletedAt.map { .double($0.timeIntervalSince1970) } ?? .null,
            .int(note.isFavorite ? 1 : 0),
            .int(note.isPinned ? 1 : 0),
            .text(note.source.rawValue),
            .text(note.contentHash),
            .text(note.syncState.rawValue),
            .text(note.id.uuidString),
            .double(expectedUpdatedAt.timeIntervalSince1970),
        ]
        let changedRows = try await db.execute(sql, params)
        return changedRows > 0
    }

    func softDeleteNote(id: UUID) async throws {
        try await db.execute(
            "UPDATE note SET deleted_at = ? WHERE id = ?;",
            [.double(Date().timeIntervalSince1970), .text(id.uuidString)]
        )
    }

    func restoreNote(id: UUID) async throws {
        try await db.execute(
            "UPDATE note SET deleted_at = NULL WHERE id = ?;",
            [.text(id.uuidString)]
        )
    }

    func purgeExpiredTrash(olderThan cutoff: Date) async throws {
        try await db.execute(
            "DELETE FROM note WHERE deleted_at IS NOT NULL AND deleted_at < ?;",
            [.double(cutoff.timeIntervalSince1970)]
        )
    }

    func deleteNotePermanently(id: UUID) async throws {
        try await db.execute("DELETE FROM note WHERE id = ?;", [.text(id.uuidString)])
    }

    func setFavorite(id: UUID, isFavorite: Bool) async throws {
        try await db.execute(
            "UPDATE note SET is_favorite = ? WHERE id = ?;",
            [.int(isFavorite ? 1 : 0), .text(id.uuidString)]
        )
    }
}
