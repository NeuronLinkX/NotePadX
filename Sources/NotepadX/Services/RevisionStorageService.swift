import Foundation

struct RevisionStorageStats: Sendable, Equatable {
    /// DB 파일(+ WAL)이 디스크에서 차지하는 크기.
    let databaseBytes: Int64
    let noteBytes: Int64
    /// 버전 기록 본문 + 따로 저장된 이미지.
    let revisionBytes: Int64
    let revisionCount: Int
    /// 아직 이미지가 문서 안에 통째로 들어 있는(= 정리하면 줄어드는) 버전 기록 수.
    let inlineImageRevisionCount: Int
}

struct RevisionCompactionReport: Sendable, Equatable {
    let convertedRevisions: Int
    let databaseBytesBefore: Int64
    let databaseBytesAfter: Int64
    var savedBytes: Int64 { max(0, databaseBytesBefore - databaseBytesAfter) }
}

/// 버전 기록 저장 공간 점검과 정리. 정리는 "이미지를 한 번만 저장"하도록 기존 기록을 바꾸는 일이라
/// 항상 무손실 검증을 거치고, 호출하는 쪽이 먼저 안전 백업을 만든 뒤에만 부른다.
enum RevisionStorageService {
    static func fileBytes(of db: DatabaseManager) -> Int64 {
        let path = db.databaseURL.path
        return ["", "-wal"].reduce(Int64(0)) { total, suffix in
            let size = (try? FileManager.default.attributesOfItem(atPath: path + suffix)[.size] as? NSNumber)?.int64Value ?? 0
            return total + size
        }
    }

    static func stats(_ db: DatabaseManager) async throws -> RevisionStorageStats {
        func scalar(_ sql: String) async throws -> Int64 {
            try await db.query(sql) { $0.int64(0) ?? 0 }.first ?? 0
        }
        let noteBytes = try await scalar("SELECT COALESCE(SUM(length(document_json)), 0) FROM note;")
        let revisionDocs = try await scalar("SELECT COALESCE(SUM(length(document_json)), 0) FROM note_revision;")
        let blobs = try await scalar("SELECT COALESCE(SUM(length(data)), 0) FROM revision_blob;")
        let count = try await scalar("SELECT COUNT(*) FROM note_revision;")
        let inline = try await scalar("SELECT COUNT(*) FROM note_revision WHERE instr(document_json, 'data:image') > 0;")
        return RevisionStorageStats(
            databaseBytes: fileBytes(of: db),
            noteBytes: noteBytes,
            revisionBytes: revisionDocs + blobs,
            revisionCount: Int(count),
            inlineImageRevisionCount: Int(inline)
        )
    }

    /// 정리할 만한(이미지가 인라인으로 든) 버전 기록이 있는지.
    static func needsCompaction(_ db: DatabaseManager) async throws -> Bool {
        let count = try await db.query(
            "SELECT COUNT(*) FROM note_revision WHERE instr(document_json, 'data:image') > 0;"
        ) { $0.int(0) ?? 0 }.first ?? 0
        return count > 0
    }

    @discardableResult
    static func compact(_ db: DatabaseManager, vacuum: Bool = true) async throws -> RevisionCompactionReport {
        let before = fileBytes(of: db)
        let ids = try await db.query(
            "SELECT id FROM note_revision WHERE instr(document_json, 'data:image') > 0;"
        ) { $0.string(0) ?? "" }

        var converted = 0
        for id in ids where !id.isEmpty {
            // 한 건씩 따로 처리한다 — 큰 문서 하나를 만지는 동안 DB를 오래 붙잡지 않고, 중간에 멈춰도
            // 이미 바꾼 것은 온전하다.
            let rows: [Data?] = try await db.query(
                "SELECT document_json FROM note_revision WHERE id = ?;", [.text(id)]
            ) { $0.blob(0) }
            guard let raw = rows.first.flatMap({ $0 }), let original = String(data: raw, encoding: .utf8) else { continue }

            let extracted = RevisionBlobCodec.extract(from: original)
            guard !extracted.blobs.isEmpty else { continue }

            // 무손실 검증: 되돌렸을 때 원본과 한 글자라도 다르면 이 기록은 건드리지 않는다.
            let restored = RevisionBlobCodec.hydrate(extracted.compacted) { extracted.blobs[$0] }
            guard restored == original, Data(restored.utf8) == raw else { continue }

            var statements: [(sql: String, bindings: [DatabaseValue])] = extracted.blobs.map {
                SQLiteNoteRevisionRepository.blobInsert(hash: $0.key, original: $0.value)
            }
            statements.append((
                "UPDATE note_revision SET document_json = ? WHERE id = ?;",
                [.blob(Data(extracted.compacted.utf8)), .text(id)]
            ))
            try await db.transaction(statements)
            converted += 1
        }

        try await SQLiteNoteRevisionRepository.purgeOrphanBlobs(db)
        if vacuum && converted > 0 { try await db.compact() }
        return RevisionCompactionReport(convertedRevisions: converted, databaseBytesBefore: before, databaseBytesAfter: fileBytes(of: db))
    }
}
