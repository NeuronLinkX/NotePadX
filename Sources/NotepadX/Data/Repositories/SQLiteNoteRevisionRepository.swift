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
        // 큰 인라인 이미지는 해시 참조로 바꿔 저장하고 실제 이미지는 revision_blob에 한 번만 둔다.
        // 이미지가 없는 문서는 바이트를 건드리지 않고 그대로 저장한다.
        var storedDocument = revision.documentJSON
        var statements: [(sql: String, bindings: [DatabaseValue])] = []
        if let json = String(data: revision.documentJSON, encoding: .utf8) {
            let extracted = RevisionBlobCodec.extract(from: json)
            if !extracted.blobs.isEmpty {
                storedDocument = Data(extracted.compacted.utf8)
                for (hash, original) in extracted.blobs {
                    statements.append(Self.blobInsert(hash: hash, original: original))
                }
            }
        }
        statements.append((
            """
            INSERT INTO note_revision (id, note_id, document_json, plain_text, reason, created_at)
            VALUES (?, ?, ?, ?, ?, ?);
            """,
            [
                .text(revision.id.uuidString),
                .text(revision.noteID.uuidString),
                .blob(storedDocument),
                .text(revision.plainText),
                .text(revision.reason.rawValue),
                .double(revision.createdAt.timeIntervalSince1970),
            ]
        ))
        try await db.transaction(statements)
    }

    static func blobInsert(hash: String, original: String) -> (sql: String, bindings: [DatabaseValue]) {
        (
            "INSERT OR IGNORE INTO revision_blob (hash, data, original_length) VALUES (?, ?, ?);",
            [.text(hash), .blob(RevisionBlobCodec.encodeForStorage(original)), .int(Int64(original.utf8.count))]
        )
    }

    /// 읽을 때는 참조를 원래 이미지로 되돌려, 위쪽 계층은 저장 방식이 바뀐 줄도 모르게 한다.
    private func hydrated(_ revisions: [NoteRevision]) async throws -> [NoteRevision] {
        var wanted = Set<String>()
        for revision in revisions {
            guard let json = String(data: revision.documentJSON, encoding: .utf8) else { continue }
            wanted.formUnion(RevisionBlobCodec.referencedHashes(in: json))
        }
        guard !wanted.isEmpty else { return revisions }

        let placeholders = Array(repeating: "?", count: wanted.count).joined(separator: ",")
        let rows: [(String, String)] = try await db.query(
            "SELECT hash, data FROM revision_blob WHERE hash IN (\(placeholders));",
            wanted.map { DatabaseValue.text($0) }
        ) { row in
            (row.string(0) ?? "", row.blob(1).flatMap(RevisionBlobCodec.decodeFromStorage) ?? "")
        }
        var lookup: [String: String] = [:]
        for (hash, text) in rows where !text.isEmpty { lookup[hash] = text }

        return revisions.map { revision in
            guard let json = String(data: revision.documentJSON, encoding: .utf8) else { return revision }
            var copy = revision
            copy.documentJSON = Data(RevisionBlobCodec.hydrate(json) { lookup[$0] }.utf8)
            return copy
        }
    }

    func revisions(forNote noteID: UUID) async throws -> [NoteRevision] {
        let raw: [NoteRevision] = try await db.query(
            """
            SELECT id, note_id, document_json, plain_text, reason, created_at
            FROM note_revision WHERE note_id = ? ORDER BY created_at DESC;
            """,
            [.text(noteID.uuidString)],
            map: mapRow
        )
        return try await hydrated(raw)
    }

    func revision(id: UUID) async throws -> NoteRevision? {
        let raw: [NoteRevision] = try await db.query(
            "SELECT id, note_id, document_json, plain_text, reason, created_at FROM note_revision WHERE id = ? LIMIT 1;",
            [.text(id.uuidString)],
            map: mapRow
        )
        return try await hydrated(raw).first
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
        try await Self.purgeOrphanBlobs(db)
    }

    /// 어떤 버전 기록도 더 이상 참조하지 않는 이미지를 지운다(오래된 기록이 정리되거나 노트가 삭제된 뒤).
    static func purgeOrphanBlobs(_ db: DatabaseManager) async throws {
        try await db.execute(
            """
            DELETE FROM revision_blob WHERE NOT EXISTS (
                SELECT 1 FROM note_revision r
                WHERE instr(r.document_json, 'notepadx-blob:' || revision_blob.hash) > 0
            );
            """
        )
    }
}
