import Foundation

/// 순서가 있는 마이그레이션 목록을 관리하고, `schema_version` 테이블에 기록된
/// 현재 버전 이후의 것만 순서대로 적용한다.
struct SchemaMigration: Sendable {
    let version: Int
    let statements: [String]
}

enum SchemaMigrator {
    /// Phase 1: Note/Folder 핵심 테이블.
    /// 이후 Phase(태그, 첨부파일, 리비전, FTS5)는 새 버전 번호로 추가되며
    /// 기존 마이그레이션은 절대 수정하지 않는다.
    static let migrations: [SchemaMigration] = [
        SchemaMigration(version: 1, statements: [
            """
            CREATE TABLE IF NOT EXISTS folder (
                id TEXT PRIMARY KEY NOT NULL,
                parent_id TEXT REFERENCES folder(id) ON DELETE CASCADE,
                name TEXT NOT NULL,
                color_hex TEXT,
                icon_system_name TEXT NOT NULL DEFAULT 'folder',
                sort_index INTEGER NOT NULL DEFAULT 0,
                is_expanded INTEGER NOT NULL DEFAULT 1,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS note (
                id TEXT PRIMARY KEY NOT NULL,
                folder_id TEXT REFERENCES folder(id) ON DELETE SET NULL,
                title TEXT NOT NULL DEFAULT '',
                document_json BLOB NOT NULL,
                plain_text TEXT NOT NULL DEFAULT '',
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                deleted_at REAL,
                is_favorite INTEGER NOT NULL DEFAULT 0,
                is_pinned INTEGER NOT NULL DEFAULT 0,
                source TEXT NOT NULL DEFAULT 'local',
                content_hash TEXT NOT NULL DEFAULT '',
                sync_state TEXT NOT NULL DEFAULT 'notSynced'
            );
            """,
            "CREATE INDEX IF NOT EXISTS idx_note_folder ON note(folder_id);",
            "CREATE INDEX IF NOT EXISTS idx_note_updated_at ON note(updated_at);",
            "CREATE INDEX IF NOT EXISTS idx_note_deleted_at ON note(deleted_at);",
            "CREATE INDEX IF NOT EXISTS idx_folder_parent ON folder(parent_id);",
        ]),
        // Phase 3: 태그, 버전 기록, FTS5 전문 검색.
        SchemaMigration(version: 2, statements: [
            """
            CREATE TABLE IF NOT EXISTS tag (
                id TEXT PRIMARY KEY NOT NULL,
                name TEXT NOT NULL UNIQUE,
                color_hex TEXT,
                created_at REAL NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS note_tag (
                note_id TEXT NOT NULL REFERENCES note(id) ON DELETE CASCADE,
                tag_id TEXT NOT NULL REFERENCES tag(id) ON DELETE CASCADE,
                PRIMARY KEY (note_id, tag_id)
            );
            """,
            "CREATE INDEX IF NOT EXISTS idx_note_tag_tag ON note_tag(tag_id);",
            """
            CREATE TABLE IF NOT EXISTS note_revision (
                id TEXT PRIMARY KEY NOT NULL,
                note_id TEXT NOT NULL REFERENCES note(id) ON DELETE CASCADE,
                document_json BLOB NOT NULL,
                plain_text TEXT NOT NULL DEFAULT '',
                reason TEXT NOT NULL,
                created_at REAL NOT NULL
            );
            """,
            "CREATE INDEX IF NOT EXISTS idx_note_revision_note ON note_revision(note_id, created_at DESC);",
            // trigram 토크나이저는 CJK(한글 포함)를 3글자 단위 부분일치로 색인해
            // unicode61(어절 단위 토큰화)보다 한글 검색에 훨씬 안정적으로 동작한다.
            // note_fts는 note.id(TEXT UUID)를 rowid로 쓸 수 없어 external content 연동 대신
            // note_id를 UNINDEXED 컬럼으로 두고 SearchIndexService가 수동으로 동기화한다.
            """
            CREATE VIRTUAL TABLE IF NOT EXISTS note_fts USING fts5(
                note_id UNINDEXED,
                title,
                body,
                tags,
                folder_name,
                tokenize = 'trigram'
            );
            """,
        ]),
        // Phase 6: OneDrive 폴더 동기화. 3-way 충돌 감지의 기준값(base)을 노트별로 보관한다.
        SchemaMigration(version: 3, statements: [
            """
            CREATE TABLE IF NOT EXISTS note_sync_state (
                note_id TEXT PRIMARY KEY NOT NULL REFERENCES note(id) ON DELETE CASCADE,
                last_synced_content_hash TEXT,
                last_synced_updated_at REAL,
                last_synced_at REAL NOT NULL,
                remote_device_id TEXT
            );
            """,
        ]),
    ]

    static func migrate(_ db: DatabaseManager) async throws {
        try await db.execute("""
            CREATE TABLE IF NOT EXISTS schema_version (
                version INTEGER PRIMARY KEY NOT NULL
            );
            """)

        let currentVersion = try await db.query(
            "SELECT MAX(version) AS v FROM schema_version;"
        ) { row in row.int(0) ?? 0 }.first ?? 0

        for migration in migrations.sorted(by: { $0.version < $1.version }) where migration.version > currentVersion {
            try await db.transaction(
                migration.statements.map { (sql: $0, bindings: []) }
                    + [(sql: "INSERT INTO schema_version (version) VALUES (?);", bindings: [.int(Int64(migration.version))])]
            )
        }
    }
}
