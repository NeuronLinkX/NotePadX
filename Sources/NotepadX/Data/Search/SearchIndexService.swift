import Foundation

/// note_fts(FTS5, trigram 토크나이저)를 note/tag/folder 테이블과 수동으로 동기화하고,
/// 검색 질의를 실행한다. external content 테이블 연동 대신 DELETE+INSERT로 동기화하는 이유는
/// note.id가 TEXT(UUID)라 FTS5가 요구하는 정수 rowid와 바로 맞지 않기 때문이다 (SchemaMigrator 참고).
actor SearchIndexService {
    private let db: DatabaseManager

    init(db: DatabaseManager) {
        self.db = db
    }

    /// 노트 하나를 색인에 반영한다. 휴지통에 있으면(삭제됨) 색인에서 제거한다.
    func reindexNote(id: UUID) async throws {
        struct Info {
            let title: String
            let plainText: String
            let deletedAt: Date?
            let folderName: String?
        }

        let rows = try await db.query(
            """
            SELECT n.title, n.plain_text, n.deleted_at, f.name
            FROM note n LEFT JOIN folder f ON f.id = n.folder_id
            WHERE n.id = ?;
            """,
            [.text(id.uuidString)]
        ) { row in
            Info(
                title: row.string(0) ?? "",
                plainText: row.string(1) ?? "",
                deletedAt: row.date(2),
                folderName: row.string(3)
            )
        }

        try await db.execute("DELETE FROM note_fts WHERE note_id = ?;", [.text(id.uuidString)])

        guard let info = rows.first, info.deletedAt == nil else { return }

        let tagNames = try await db.query(
            """
            SELECT t.name FROM tag t JOIN note_tag nt ON nt.tag_id = t.id
            WHERE nt.note_id = ? ORDER BY t.name;
            """,
            [.text(id.uuidString)]
        ) { $0.string(0) ?? "" }

        try await db.execute(
            "INSERT INTO note_fts (note_id, title, body, tags, folder_name) VALUES (?, ?, ?, ?, ?);",
            [
                .text(id.uuidString),
                .text(info.title),
                .text(info.plainText),
                .text(tagNames.joined(separator: " ")),
                .text(info.folderName ?? ""),
            ]
        )
    }

    func removeFromIndex(id: UUID) async throws {
        try await db.execute("DELETE FROM note_fts WHERE note_id = ?;", [.text(id.uuidString)])
    }

    /// 폴더 이름이 바뀌면 그 폴더에 속한 모든 노트의 색인을 다시 만든다.
    func reindexAllNotes(folderID: UUID) async throws {
        let ids: [UUID] = try await db.query(
            "SELECT id FROM note WHERE folder_id = ? AND deleted_at IS NULL;",
            [.text(folderID.uuidString)]
        ) { UUID(uuidString: $0.string(0) ?? "") }.compactMap { $0 }
        for id in ids {
            try await reindexNote(id: id)
        }
    }

    func search(query: String, filters: SearchFilters = SearchFilters(), limit: Int = 200) async throws -> [SearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let (extraWhere, extraBindings, extraJoin) = filterClause(filters)

        if trimmed.count < 3 {
            // trigram 토크나이저는 3글자 미만 질의에서는 트라이그램을 만들 수 없어 매칭이 안 된다.
            // 이 경우에만 LIKE로 대체한다 (짧은 질의라 성능 영향은 미미하다).
            let pattern = "%\(escapeLike(trimmed))%"
            let sql = """
                SELECT n.id, n.title, n.plain_text, n.updated_at
                FROM note n \(extraJoin)
                WHERE n.deleted_at IS NULL AND (n.title LIKE ? ESCAPE '\\' OR n.plain_text LIKE ? ESCAPE '\\') \(extraWhere)
                ORDER BY n.updated_at DESC LIMIT ?;
                """
            let bindings: [DatabaseValue] = [.text(pattern), .text(pattern)] + extraBindings + [.int(Int64(limit))]
            return try await db.query(sql, bindings, map: mapHitRow)
        }

        let escapedQuery = trimmed.replacingOccurrences(of: "\"", with: "\"\"")
        let ftsQuery = "\"\(escapedQuery)\""
        let sql = """
            SELECT n.id, n.title, n.plain_text, n.updated_at
            FROM note_fts JOIN note n ON n.id = note_fts.note_id \(extraJoin)
            WHERE note_fts MATCH ? AND n.deleted_at IS NULL \(extraWhere)
            ORDER BY rank LIMIT ?;
            """
        let bindings: [DatabaseValue] = [.text(ftsQuery)] + extraBindings + [.int(Int64(limit))]
        return try await db.query(sql, bindings, map: mapHitRow)
    }

    private func mapHitRow(_ row: StatementRow) -> SearchHit {
        let id = UUID(uuidString: row.string(0) ?? "") ?? UUID()
        let title = row.string(1) ?? ""
        return SearchHit(
            noteID: id,
            title: title.isEmpty ? "제목 없음" : title,
            snippet: row.string(2) ?? "",
            updatedAt: row.date(3) ?? Date()
        )
    }

    private func escapeLike(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    /// note_tag를 태그 필터일 때만 조인한다 — 특정 tag_id 하나로만 필터링하므로
    /// (note_id, tag_id)가 PK라 조인으로 인한 행 중복은 생기지 않는다.
    private func filterClause(_ filters: SearchFilters) -> (where: String, bindings: [DatabaseValue], join: String) {
        var clauses: [String] = []
        var bindings: [DatabaseValue] = []
        var join = ""

        if let folderID = filters.folderID {
            clauses.append("n.folder_id = ?")
            bindings.append(.text(folderID.uuidString))
        }
        if let tagID = filters.tagID {
            join = "JOIN note_tag ON note_tag.note_id = n.id"
            clauses.append("note_tag.tag_id = ?")
            bindings.append(.text(tagID.uuidString))
        }
        if filters.favoritesOnly {
            clauses.append("n.is_favorite = 1")
        }
        if let createdAfter = filters.createdAfter {
            clauses.append("n.created_at >= ?")
            bindings.append(.double(createdAfter.timeIntervalSince1970))
        }
        if let createdBefore = filters.createdBefore {
            clauses.append("n.created_at <= ?")
            bindings.append(.double(createdBefore.timeIntervalSince1970))
        }
        if let updatedAfter = filters.updatedAfter {
            clauses.append("n.updated_at >= ?")
            bindings.append(.double(updatedAfter.timeIntervalSince1970))
        }
        if let updatedBefore = filters.updatedBefore {
            clauses.append("n.updated_at <= ?")
            bindings.append(.double(updatedBefore.timeIntervalSince1970))
        }

        let whereText = clauses.isEmpty ? "" : " AND " + clauses.joined(separator: " AND ")
        return (whereText, bindings, join)
    }
}
