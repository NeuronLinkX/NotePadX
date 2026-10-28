import Foundation
import SQLite3

/// SQLite 바인딩 파라미터를 표현하는 값 타입. GRDB 같은 외부 의존성 없이
/// 시스템 제공 SQLite3 C API 위에 얇은 Swift 래퍼를 둔다.
enum DatabaseValue: Sendable {
    case text(String)
    case int(Int64)
    case double(Double)
    case blob(Data)
    case null
}

/// 쿼리 결과 한 행에 접근하기 위한 뷰.
struct StatementRow {
    fileprivate let statement: OpaquePointer

    func string(_ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let cString = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: cString)
    }

    func int64(_ index: Int32) -> Int64? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return sqlite3_column_int64(statement, index)
    }

    func int(_ index: Int32) -> Int? {
        int64(index).map(Int.init)
    }

    func double(_ index: Int32) -> Double? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return sqlite3_column_double(statement, index)
    }

    func bool(_ index: Int32) -> Bool? {
        int64(index).map { $0 != 0 }
    }

    func blob(_ index: Int32) -> Data? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        guard let bytes = sqlite3_column_blob(statement, index) else { return Data() }
        let count = Int(sqlite3_column_bytes(statement, index))
        return Data(bytes: bytes, count: count)
    }

    func date(_ index: Int32) -> Date? {
        double(index).map { Date(timeIntervalSince1970: $0) }
    }
}

enum DatabaseError: LocalizedError, Sendable {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case bindFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let msg): return "데이터베이스를 열 수 없습니다: \(msg)"
        case .prepareFailed(let msg): return "쿼리를 준비할 수 없습니다: \(msg)"
        case .stepFailed(let msg): return "쿼리 실행에 실패했습니다: \(msg)"
        case .bindFailed(let msg): return "파라미터 바인딩에 실패했습니다: \(msg)"
        }
    }
}

/// 단일 SQLite 연결을 액터로 감싸 모든 접근을 직렬화한다.
/// 메인 스레드 블로킹 없이 비동기로 호출되며, Data 계층 상위(Repository)에서만 사용한다.
actor DatabaseManager {
    private var db: OpaquePointer?
    let databaseURL: URL

    init(databaseURL: URL) throws {
        self.databaseURL = databaseURL
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &handle, flags, nil) == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            throw DatabaseError.openFailed(message)
        }
        self.db = handle
        sqlite3_exec(handle, "PRAGMA foreign_keys = ON;", nil, nil, nil)
        sqlite3_exec(handle, "PRAGMA journal_mode = WAL;", nil, nil, nil)
    }

    deinit {
        if let db { sqlite3_close_v2(db) }
    }

    private func lastErrorMessage() -> String {
        guard let db else { return "no connection" }
        return String(cString: sqlite3_errmsg(db))
    }

    private func bind(_ values: [DatabaseValue], to statement: OpaquePointer) throws {
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch value {
            case .text(let string):
                result = sqlite3_bind_text(statement, index, string, -1, SQLITE_TRANSIENT)
            case .int(let intValue):
                result = sqlite3_bind_int64(statement, index, intValue)
            case .double(let doubleValue):
                result = sqlite3_bind_double(statement, index, doubleValue)
            case .blob(let data):
                result = data.withUnsafeBytes { rawBuffer -> Int32 in
                    sqlite3_bind_blob(statement, index, rawBuffer.baseAddress, Int32(data.count), SQLITE_TRANSIENT)
                }
            case .null:
                result = sqlite3_bind_null(statement, index)
            }
            guard result == SQLITE_OK else {
                throw DatabaseError.bindFailed(lastErrorMessage())
            }
        }
    }

    /// INSERT/UPDATE/DELETE/DDL 등 결과 행이 없는 구문 실행.
    @discardableResult
    func execute(_ sql: String, _ bindings: [DatabaseValue] = []) throws -> Int {
        guard let db else { throw DatabaseError.openFailed("connection closed") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw DatabaseError.prepareFailed(lastErrorMessage())
        }
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_DONE || stepResult == SQLITE_ROW else {
            throw DatabaseError.stepFailed(lastErrorMessage())
        }
        return Int(sqlite3_changes(db))
    }

    /// SELECT 구문을 실행하고 각 행을 `map`으로 변환한 배열을 돌려준다.
    func query<T>(_ sql: String, _ bindings: [DatabaseValue] = [], map: (StatementRow) throws -> T) throws -> [T] {
        guard let db else { throw DatabaseError.openFailed("connection closed") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw DatabaseError.prepareFailed(lastErrorMessage())
        }
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)

        var rows: [T] = []
        while true {
            let stepResult = sqlite3_step(statement)
            if stepResult == SQLITE_ROW {
                rows.append(try map(StatementRow(statement: statement)))
            } else if stepResult == SQLITE_DONE {
                break
            } else {
                throw DatabaseError.stepFailed(lastErrorMessage())
            }
        }
        return rows
    }

    /// 여러 구문을 하나의 트랜잭션으로 원자적으로 실행한다.
    ///
    /// 클로저 기반 트랜잭션 대신 (sql, bindings) 목록을 받는 방식을 쓴다. 액터 메서드를
    /// async 클로저로 재진입시키면 BEGIN과 COMMIT 사이에 다른 태스크가 같은 액터에 끼어들
    /// 여지가 생기므로, 이 메서드 안에서 완전히 동기적으로 모든 구문을 실행해 원자성을 보장한다.
    func transaction(_ statements: [(sql: String, bindings: [DatabaseValue])]) throws {
        guard let db else { throw DatabaseError.openFailed("connection closed") }
        guard sqlite3_exec(db, "BEGIN IMMEDIATE TRANSACTION;", nil, nil, nil) == SQLITE_OK else {
            throw DatabaseError.stepFailed(lastErrorMessage())
        }
        do {
            for statement in statements {
                try execute(statement.sql, statement.bindings)
            }
            guard sqlite3_exec(db, "COMMIT;", nil, nil, nil) == SQLITE_OK else {
                throw DatabaseError.stepFailed(lastErrorMessage())
            }
        } catch {
            sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
            throw error
        }
    }
}

extension DatabaseManager {
    /// SQLite 온라인 백업 API로 지금 열려 있는 DB의 일관된 스냅샷을 `destination`에 만든다. 파일을
    /// 그냥 복사하면 아직 WAL에만 있는 최근 변경이 빠지거나 쓰는 도중의 파일이 복사될 수 있지만,
    /// 이 방법은 항상 한 시점의 완전한 DB를 만든다. 결과 파일은 -wal/-shm 없이 단독으로 열린다.
    func backup(to destination: URL) throws {
        guard let db else { throw DatabaseError.openFailed("connection closed") }
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: destination)

        var target: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(destination.path, &target, flags, nil) == SQLITE_OK, let target else {
            let message = target.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            if let target { sqlite3_close_v2(target) }
            throw DatabaseError.openFailed(message)
        }

        guard let copier = sqlite3_backup_init(target, "main", db, "main") else {
            let message = String(cString: sqlite3_errmsg(target))
            sqlite3_close_v2(target)
            throw DatabaseError.stepFailed(message)
        }
        var result = sqlite3_backup_step(copier, -1)
        var retries = 0
        while (result == SQLITE_BUSY || result == SQLITE_LOCKED) && retries < 50 {
            sqlite3_sleep(100)
            retries += 1
            result = sqlite3_backup_step(copier, -1)
        }
        sqlite3_backup_finish(copier)
        sqlite3_close_v2(target)
        guard result == SQLITE_DONE else {
            try? fileManager.removeItem(at: destination)
            throw DatabaseError.stepFailed("backup step failed (\(result))")
        }

        // 백업은 원본의 헤더("WAL 모드")까지 그대로 복사한다. 방금 연 연결은 그 사실을 모르기 때문에 같은
        // 연결에서 journal_mode를 바꾸면 아무 일도 안 일어난다 — 닫고 다시 열어야 WAL을 읽고 DELETE로
        // 바꿀 수 있다. 그래야 백업이 -wal/-shm 없이 파일 하나로 단독으로 열린다.
        var reopened: OpaquePointer?
        if sqlite3_open_v2(destination.path, &reopened, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK {
            sqlite3_exec(reopened, "PRAGMA journal_mode = DELETE;", nil, nil, nil)
        }
        if let reopened { sqlite3_close_v2(reopened) }
        // WAL에서 빠져나온 뒤에도 빈 -shm 파일이 남는다. 열린 연결이 없고 파일이 이미 단독 모드이므로 지워도 안전하다.
        for suffix in ["-wal", "-shm"] {
            try? fileManager.removeItem(atPath: destination.path + suffix)
        }
    }

    /// `PRAGMA quick_check` — 페이지/인덱스 구조가 온전한지 빠르게 확인한다. 문제가 없으면 ["ok"].
    func quickCheck() throws -> [String] {
        try query("PRAGMA quick_check;") { $0.string(0) ?? "" }
    }

    /// 지워진 데이터가 차지하던 공간을 파일에서 실제로 돌려준다(WAL 정리 후 VACUUM).
    func compact() throws {
        guard let db else { throw DatabaseError.openFailed("connection closed") }
        sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE);", nil, nil, nil)
        guard sqlite3_exec(db, "VACUUM;", nil, nil, nil) == SQLITE_OK else {
            throw DatabaseError.stepFailed(String(cString: sqlite3_errmsg(db)))
        }
        // WAL 모드에서 VACUUM은 줄어든 DB를 로그(-wal)에 쓸 뿐이라, 한 번 더 체크포인트해야 본 파일이
        // 실제로 작아진다.
        sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE);", nil, nil, nil)
    }

    /// 파일로 존재하는 DB(백업본 등)를 읽기 전용으로 열어 quick_check만 한다 — 복원하기 전에
    /// 그 백업이 정말 열리고 온전한지 확인하는 용도.
    static func verifyFile(at url: URL) -> Bool {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let handle else {
            if let handle { sqlite3_close_v2(handle) }
            return false
        }
        defer { sqlite3_close_v2(handle) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "PRAGMA quick_check;", -1, &statement, nil) == SQLITE_OK, let statement else { return false }
        defer { sqlite3_finalize(statement) }
        var sawRow = false
        while sqlite3_step(statement) == SQLITE_ROW {
            sawRow = true
            guard let text = sqlite3_column_text(statement, 0), String(cString: text) == "ok" else { return false }
        }
        return sawRow
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
