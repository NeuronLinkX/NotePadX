import Foundation

struct SQLiteFolderRepository: FolderRepository {
    private let db: DatabaseManager

    init(db: DatabaseManager) {
        self.db = db
    }

    private func mapRow(_ row: StatementRow) throws -> Folder {
        guard let idString = row.string(0), let id = UUID(uuidString: idString) else {
            throw AppError.documentCorrupted
        }
        return Folder(
            id: id,
            parentID: row.string(1).flatMap(UUID.init(uuidString:)),
            name: row.string(2) ?? "",
            colorHex: row.string(3),
            iconSystemName: row.string(4) ?? "folder",
            sortIndex: row.int(5) ?? 0,
            isExpanded: row.bool(6) ?? true,
            createdAt: row.date(7) ?? Date(),
            updatedAt: row.date(8) ?? Date()
        )
    }

    func fetchAllFolders() async throws -> [Folder] {
        try await db.query(
            """
            SELECT id, parent_id, name, color_hex, icon_system_name, sort_index, is_expanded, created_at, updated_at
            FROM folder ORDER BY sort_index ASC, name COLLATE NOCASE ASC;
            """,
            map: mapRow
        )
    }

    func createFolder(_ folder: Folder) async throws {
        try await db.execute(
            """
            INSERT INTO folder (id, parent_id, name, color_hex, icon_system_name, sort_index, is_expanded, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            [
                .text(folder.id.uuidString),
                folder.parentID.map { .text($0.uuidString) } ?? .null,
                .text(folder.name),
                folder.colorHex.map { .text($0) } ?? .null,
                .text(folder.iconSystemName),
                .int(Int64(folder.sortIndex)),
                .int(folder.isExpanded ? 1 : 0),
                .double(folder.createdAt.timeIntervalSince1970),
                .double(folder.updatedAt.timeIntervalSince1970),
            ]
        )
    }

    func renameFolder(id: UUID, newName: String) async throws {
        try await db.execute(
            "UPDATE folder SET name = ?, updated_at = ? WHERE id = ?;",
            [.text(newName), .double(Date().timeIntervalSince1970), .text(id.uuidString)]
        )
    }

    func moveFolder(id: UUID, newParentID: UUID?) async throws {
        try await db.execute(
            "UPDATE folder SET parent_id = ?, updated_at = ? WHERE id = ?;",
            [newParentID.map { .text($0.uuidString) } ?? .null, .double(Date().timeIntervalSince1970), .text(id.uuidString)]
        )
    }

    func deleteFolder(id: UUID) async throws {
        try await db.execute("DELETE FROM folder WHERE id = ?;", [.text(id.uuidString)])
    }

    func noteCount(folderID: UUID) async throws -> Int {
        try await db.query(
            "SELECT COUNT(*) FROM note WHERE folder_id = ? AND deleted_at IS NULL;",
            [.text(folderID.uuidString)]
        ) { row in row.int(0) ?? 0 }.first ?? 0
    }
}
