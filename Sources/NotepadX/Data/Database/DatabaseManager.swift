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

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
