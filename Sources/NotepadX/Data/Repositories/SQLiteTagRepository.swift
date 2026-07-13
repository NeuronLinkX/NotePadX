import Foundation

struct SQLiteTagRepository: TagRepository {
    private let db: DatabaseManager

    init(db: DatabaseManager) {
        self.db = db
    }

    private func mapRow(_ row: StatementRow) throws -> Tag {
        guard let idString = row.string(0), let id = UUID(uuidString: idString) else {
            throw AppError.documentCorrupted
        }
        return Tag(id: id, name: row.string(1) ?? "", colorHex: row.string(2))
    }

    func fetchAllTags() async throws -> [Tag] {
        try await db.query(
            "SELECT id, name, color_hex FROM tag ORDER BY name COLLATE NOCASE ASC;",
            map: mapRow
        )
    }

    func createTag(_ tag: Tag) async throws {
        try await db.execute(
            "INSERT INTO tag (id, name, color_hex, created_at) VALUES (?, ?, ?, ?);",
            [
                .text(tag.id.uuidString),
                .text(tag.name),
                tag.colorHex.map { .text($0) } ?? .null,
                .double(Date().timeIntervalSince1970),
            ]
        )
    }

    func renameTag(id: UUID, newName: String) async throws {
        try await db.execute(
            "UPDATE tag SET name = ? WHERE id = ?;",
            [.text(newName), .text(id.uuidString)]
        )
    }

    func setColor(id: UUID, colorHex: String?) async throws {
        try await db.execute(
            "UPDATE tag SET color_hex = ? WHERE id = ?;",
            [colorHex.map { .text($0) } ?? .null, .text(id.uuidString)]
        )
    }

    func deleteTag(id: UUID) async throws {
        try await db.execute("DELETE FROM tag WHERE id = ?;", [.text(id.uuidString)])
    }

    func noteCount(tagID: UUID) async throws -> Int {
        try await db.query(
            "SELECT COUNT(*) FROM note_tag JOIN note ON note.id = note_tag.note_id WHERE note_tag.tag_id = ? AND note.deleted_at IS NULL;",
            [.text(tagID.uuidString)]
        ) { row in row.int(0) ?? 0 }.first ?? 0
    }

    func tags(forNote noteID: UUID) async throws -> [Tag] {
        try await db.query(
            """
            SELECT tag.id, tag.name, tag.color_hex FROM tag
            JOIN note_tag ON note_tag.tag_id = tag.id
            WHERE note_tag.note_id = ?
            ORDER BY tag.name COLLATE NOCASE ASC;
            """,
            [.text(noteID.uuidString)],
            map: mapRow
        )
    }

    func setTags(noteID: UUID, tagIDs: [UUID]) async throws {
        var statements: [(sql: String, bindings: [DatabaseValue])] = [
            (sql: "DELETE FROM note_tag WHERE note_id = ?;", bindings: [.text(noteID.uuidString)])
        ]
        for tagID in tagIDs {
            statements.append((
                sql: "INSERT INTO note_tag (note_id, tag_id) VALUES (?, ?);",
                bindings: [.text(noteID.uuidString), .text(tagID.uuidString)]
            ))
        }
        try await db.transaction(statements)
    }
}
