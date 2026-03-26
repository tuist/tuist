import Foundation
import Mockable
import Path
import SQLite
import TuistEnvironment

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
        let db = try Connection(dbPath.pathString)
        db.busyTimeout = 5
        try db.execute("PRAGMA journal_mode = WAL")
        try db.execute("PRAGMA synchronous = NORMAL")
        try db.run(Schema.entries.create(ifNotExists: true) { t in
            t.column(Schema.category)
            t.column(Schema.key)
            t.column(Schema.value)
            t.column(Schema.createdAt, defaultValue: Date())
            t.primaryKey(Schema.category, Schema.key)
        })
        return CASAnalyticsDatabase(db: db, path: dbPath)
    }

    private let db: Connection
    private let path: AbsolutePath

    private init(db: Connection, path: AbsolutePath) {
        self.db = db
        self.path = path
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
        try db.run(
            Schema.entries
                .filter(Schema.createdAt < date)
                .delete()
        )
    }

    public func databasePath() -> AbsolutePath {
        path
    }

    // MARK: - Private

    private func store(category: String, key: String, value: String) throws {
        try db.run(
            Schema.entries.insert(
                or: .replace,
                Schema.category <- category,
                Schema.key <- key,
                Schema.value <- value,
                Schema.createdAt <- Date()
            )
        )
    }

    private func get(category: String, key: String) throws -> String? {
        try db.pluck(
            Schema.entries
                .select(Schema.value)
                .filter(Schema.category == category && Schema.key == key)
        )?[Schema.value]
    }
}

private enum Schema {
    static let entries = Table("entries")
    static let category = SQLite.Expression<String>("category")
    static let key = SQLite.Expression<String>("key")
    static let value = SQLite.Expression<String>("value")
    static let createdAt = SQLite.Expression<Date>("created_at")
}
