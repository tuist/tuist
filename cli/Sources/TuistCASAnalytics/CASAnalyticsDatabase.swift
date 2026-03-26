import Foundation
import Mockable
import Path
import SQLite3
import TuistEnvironment

public struct NoOpCASAnalyticsDatabase: CASAnalyticsDatabasing {
    public init() {}
    public func store(category _: String, key _: String, value _: String) throws {}
    public func get(category _: String, key _: String) throws -> String? { nil }
    public func removeOldEntries(olderThan _: Date) throws {}
    public func databasePath() -> AbsolutePath {
        try! AbsolutePath(validating: "/dev/null")
    }
}

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
    func store(category: String, key: String, value: String) throws
    func get(category: String, key: String) throws -> String?
    func removeOldEntries(olderThan: Date) throws
    func databasePath() -> AbsolutePath
}

public final class CASAnalyticsDatabase: CASAnalyticsDatabasing, @unchecked Sendable {
    private static let _shared = NSLock()
    private static var _sharedInstance: CASAnalyticsDatabase?

    public static var shared: CASAnalyticsDatabase {
        get throws {
            _shared.lock()
            defer { _shared.unlock() }
            if let existing = _sharedInstance { return existing }
            let instance = try CASAnalyticsDatabase()
            _sharedInstance = instance
            return instance
        }
    }

    private let db: OpaquePointer
    private let path: AbsolutePath
    private let lock = NSLock()

    public init(stateDirectory: AbsolutePath? = nil) throws {
        let stateDir = stateDirectory ?? Environment.current.stateDirectory
        let dbPath = stateDir.appending(component: "cas_analytics.db")
        self.path = dbPath

        var dbPointer: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(dbPath.pathString, &dbPointer, flags, nil)
        guard result == SQLITE_OK, let db = dbPointer else {
            let message = dbPointer.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(dbPointer)
            throw CASAnalyticsDatabaseError.failedToOpen(message)
        }
        self.db = db

        sqlite3_busy_timeout(db, 5000)

        try execute("""
        CREATE TABLE IF NOT EXISTS entries (
            category TEXT NOT NULL,
            key TEXT NOT NULL,
            value TEXT NOT NULL,
            created_at REAL NOT NULL DEFAULT (julianday('now')),
            PRIMARY KEY (category, key)
        )
        """)

        try execute("PRAGMA journal_mode = WAL")
        try execute("PRAGMA synchronous = NORMAL")
    }

    deinit {
        sqlite3_close(db)
    }

    public func store(category: String, key: String, value: String) throws {
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

    public func get(category: String, key: String) throws -> String? {
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
