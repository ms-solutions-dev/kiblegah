import Foundation
import SQLite3
import Synchronization

/// A read-only SQLite file (content packs and other bundled data).
///
/// Packs never change at runtime, so one connection per file suffices, protected by a
/// `Mutex`. Prepared queries stay cached – otherwise most of the time of a verse lookup
/// would be compiling the SQL line.
public final class Database: Sendable {
    private struct LoadStatus: ~Copyable {
        let link: OpaquePointer
        var queries: [String: OpaquePointer] = [:]
    }

    private let status: Mutex<LoadStatus>

    public init(url: URL) throws(ContentPackError) {
        var link: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(url.path(percentEncoded: false), &link, flags, nil) == SQLITE_OK,
            let link
        else {
            sqlite3_close(link)
            throw .couldNotOpen(url.lastPathComponent)
        }
        status = Mutex(LoadStatus(link: link))
    }

    deinit {
        status.withLock { d in
            for s in d.queries.values { sqlite3_finalize(s) }
            sqlite3_close(d.link)
        }
    }

    /// Runs a query and reads each row with `row`.
    public func query<T>(
        _ sql: String, _ values: [Value] = [], row: (Row) -> T
    ) -> [T] {
        status.withLock { d -> [T] in
            let statement: OpaquePointer
            if let ready = d.queries[sql] {
                statement = ready
            } else {
                var fresh: OpaquePointer?
                guard sqlite3_prepare_v2(d.link, sql, -1, &fresh, nil) == SQLITE_OK, let fresh else {
                    return []
                }
                d.queries[sql] = fresh
                statement = fresh
            }
            defer {
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
            }
            for (i, value) in values.enumerated() {
                let place = Int32(i + 1)
                switch value {
                case .integer(let n): sqlite3_bind_int64(statement, place, Int64(n))
                case .text(let m): sqlite3_bind_text(statement, place, m, -1, Database.transient)
                case .double(let d): sqlite3_bind_double(statement, place, d)
                }
            }
            var result: [T] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                result.append(row(Row(statement: statement)))
            }
            return result
        }
    }

    public func first<T>(_ sql: String, _ values: [Value] = [], row: (Row) -> T) -> T? {
        query(sql, values, row: row).first
    }

    /// `SQLITE_TRANSIENT`: SQLite copies the text immediately.
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}

public enum Value {
    case integer(Int)
    case text(String)
    case double(Double)
}

/// Read access to the current result row; valid only within `row`.
public struct Row {
    let statement: OpaquePointer

    public func integer(_ i: Int32) -> Int { Int(sqlite3_column_int64(statement, i)) }

    public func text(_ i: Int32) -> String { optionalText(i) ?? "" }

    public func double(_ i: Int32) -> Double { sqlite3_column_double(statement, i) }

    public func data(_ i: Int32) -> Data {
        guard let b = sqlite3_column_blob(statement, i) else { return Data() }
        return Data(bytes: b, count: Int(sqlite3_column_bytes(statement, i)))
    }

    public func optionalText(_ i: Int32) -> String? {
        guard sqlite3_column_type(statement, i) != SQLITE_NULL, let c = sqlite3_column_text(statement, i)
        else {
            return nil
        }
        return String(cString: c)
    }
}
