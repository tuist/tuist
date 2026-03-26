import Foundation
import Mockable
import Path
import SQLite3
import TuistEnvironment

enum CASAnalyticsDatabaseError: LocalizedError {
    case failedToOpen(String)
    case failedToExecute(String)

    var errorDescription: String? {
        switch self {
        case let .failedToOpen(message):
            return "Failed to open CAS analytics database: \(message)"
        case let .failedToExecute(message):
            return "Failed to execute CAS analytics database query: \(message)"
        }
    }
}

@Mockable
public protocol CASAnalyticsDatabasing: Sendable {
    func storeCASOutput(key: String, value: String) throws
    func casOutput(for key: String) throws -> String?

    func storeNode(key: String, value: String) throws
    func node(for key: String) throws -> String?

    func storeKeyValueMetadata(key: String, operationType: String, value: String) throws
    func keyValueMetadata(for key: String, operationType: String) throws -> String?

    func removeOldEntries(olderThan: Date) throws
    func databasePath() -> AbsolutePath
}

public final class CASAnalyticsDatabase: CASAnalyticsDatabasing, @unchecked Sendable {
    private static let _lock = NSLock()
    private static var _shared: CASAnalyticsDatabase?

    public static var shared: CASAnalyticsDatabase {
        _lock.lock()
        defer { _lock.unlock() }
        if let existing = _shared { return existing }
        let instance = try! open()
        _shared = instance
        return instance
    }

    public static func open(stateDirectory: AbsolutePath? = nil) throws -> CASAnalyticsDatabase {
        let stateDir = stateDirectory ?? Environment.current.stateDirectory
        let dbPath = stateDir.appending(component: "cas_analytics.db")

        var dbPointer: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(dbPath.pathString, &dbPointer, flags, nil)
        guard result == SQLITE_OK, let db = dbPointer else {
            let message = dbPointer.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(dbPointer)
            throw CASAnalyticsDatabaseError.failedToOpen(message)
        }

        sqlite3_busy_timeout(db, 5000)

        let instance = CASAnalyticsDatabase(db: db, path: dbPath)
        try instance.execute("PRAGMA journal_mode = WAL")
        try instance.execute("PRAGMA synchronous = NORMAL")
        try instance.execute("""
        CREATE TABLE IF NOT EXISTS entries (
            category TEXT NOT NULL,
            key TEXT NOT NULL,
            value TEXT NOT NULL,
            created_at REAL NOT NULL DEFAULT (julianday('now')),
            PRIMARY KEY (category, key)
        )
        """)
        return instance
    }

    private let db: OpaquePointer
    private let path: AbsolutePath
    private let lock = NSLock()

    private init(db: OpaquePointer, path: AbsolutePath) {
        self.db = db
        self.path = path
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - CAS Outputs

    public func storeCASOutput(key: String, value: String) throws {
        try store(category: "cas", key: key, value: value)
    }

    public func casOutput(for key: String) throws -> String? {
        try get(category: "cas", key: key)
    }

    // MARK: - Nodes

    public func storeNode(key: String, value: String) throws {
        try store(category: "nodes", key: key, value: value)
    }

    public func node(for key: String) throws -> String? {
        try get(category: "nodes", key: key)
    }

    // MARK: - KeyValue Metadata

    public func storeKeyValueMetadata(key: String, operationType: String, value: String) throws {
        try store(category: "keyvalue_\(operationType)", key: key, value: value)
    }

    public func keyValueMetadata(for key: String, operationType: String) throws -> String? {
        try get(category: "keyvalue_\(operationType)", key: key)
    }

    // MARK: - Maintenance

    public func removeOldEntries(olderThan date: Date) throws {
        lock.lock()
        defer { lock.unlock() }

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        let sql = "DELETE FROM entries WHERE created_at < julianday(?)"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw CASAnalyticsDatabaseError.failedToExecute(String(cString: sqlite3_errmsg(db)))
        }

        let formatter = ISO8601DateFormatter()
        let dateString = formatter.string(from: date)
        sqlite3_bind_text(stmt, 1, (dateString as NSString).utf8String, -1, nil)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw CASAnalyticsDatabaseError.failedToExecute(String(cString: sqlite3_errmsg(db)))
        }
    }

    public func databasePath() -> AbsolutePath {
        path
    }

    // MARK: - Private

    private func store(category: String, key: String, value: String) throws {
        lock.lock()
        defer { lock.unlock() }

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        let sql = "INSERT OR REPLACE INTO entries (category, key, value, created_at) VALUES (?, ?, ?, julianday('now'))"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw CASAnalyticsDatabaseError.failedToExecute(String(cString: sqlite3_errmsg(db)))
        }

        sqlite3_bind_text(stmt, 1, (category as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (key as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (value as NSString).utf8String, -1, nil)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw CASAnalyticsDatabaseError.failedToExecute(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func get(category: String, key: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        let sql = "SELECT value FROM entries WHERE category = ? AND key = ?"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw CASAnalyticsDatabaseError.failedToExecute(String(cString: sqlite3_errmsg(db)))
        }

        sqlite3_bind_text(stmt, 1, (category as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (key as NSString).utf8String, -1, nil)

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return nil
        }

        guard let cString = sqlite3_column_text(stmt, 0) else {
            return nil
        }
        return String(cString: cString)
    }

    private func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)
        if result != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(errorMessage)
            throw CASAnalyticsDatabaseError.failedToExecute(message)
        }
    }
}
