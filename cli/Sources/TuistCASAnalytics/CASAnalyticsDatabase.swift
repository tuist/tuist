import CASAnalyticsDatabase // re-exports SQLite
import Foundation
import Mockable
import Path
import TuistEnvironment

public enum KeyValueOperationType: String, Codable {
    case read
    case write
}

@Mockable
public protocol CASAnalyticsDatabasing: Sendable {
    func storeCASOutput(key: String, size: Int, duration: TimeInterval, compressedSize: Int) throws
    func casOutput(for key: String) throws -> CASOutputMetadata?

    func storeNode(key: String, checksum: String) throws
    func node(for key: String) throws -> String?

    func storeKeyValueMetadata(key: String, operationType: String, duration: TimeInterval) throws
    func keyValueMetadata(for key: String, operationType: String) throws -> KeyValueMetadata?

    func migrate() throws
    func removeOldEntries(olderThan: Date) throws
}

public struct CASAnalyticsDatabase: CASAnalyticsDatabasing {
    public static let databaseName = "cas_analytics.db"

    private let db: Connection

    public init() throws {
        let stateDirectory = Environment.current.stateDirectory
        try FileManager.default.createDirectory(
            atPath: stateDirectory.pathString,
            withIntermediateDirectories: true
        )
        db = try Connection(
            stateDirectory.appending(component: Self.databaseName).pathString
        )
        db.busyTimeout = 5
        try db.execute("PRAGMA synchronous = NORMAL")
        try db.execute("PRAGMA wal_autocheckpoint = 1")
    }

    public func migrate() throws {
        try db.execute("PRAGMA journal_mode = WAL")
        try db.run(CASOutputsSchema.table.create(ifNotExists: true) { t in
            t.column(CASOutputsSchema.key, primaryKey: true)
            t.column(CASOutputsSchema.size)
            t.column(CASOutputsSchema.duration)
            t.column(CASOutputsSchema.compressedSize)
            t.column(CASOutputsSchema.createdAt, defaultValue: Date())
        })

        try db.run(NodesSchema.table.create(ifNotExists: true) { t in
            t.column(NodesSchema.key, primaryKey: true)
            t.column(NodesSchema.checksum)
            t.column(NodesSchema.createdAt, defaultValue: Date())
        })

        try db.run(KeyValueMetadataSchema.table.create(ifNotExists: true) { t in
            t.column(KeyValueMetadataSchema.key)
            t.column(KeyValueMetadataSchema.operationType)
            t.column(KeyValueMetadataSchema.duration)
            t.column(KeyValueMetadataSchema.createdAt, defaultValue: Date())
            t.primaryKey(KeyValueMetadataSchema.key, KeyValueMetadataSchema.operationType)
        })
    }

    // MARK: - CAS Outputs

    public func storeCASOutput(key: String, size: Int, duration: TimeInterval, compressedSize: Int) throws {
        try db.run(CASOutputsSchema.table.insert(
            or: .replace,
            CASOutputsSchema.key <- key,
            CASOutputsSchema.size <- size,
            CASOutputsSchema.duration <- duration,
            CASOutputsSchema.compressedSize <- compressedSize,
            CASOutputsSchema.createdAt <- Date()
        ))
    }

    public func casOutput(for key: String) throws -> CASOutputMetadata? {
        guard let row = try db.pluck(
            CASOutputsSchema.table.filter(CASOutputsSchema.key == key)
        ) else { return nil }
        return CASOutputMetadata(
            size: row[CASOutputsSchema.size],
            duration: row[CASOutputsSchema.duration],
            compressedSize: row[CASOutputsSchema.compressedSize]
        )
    }

    // MARK: - Nodes

    public func storeNode(key: String, checksum: String) throws {
        try db.run(NodesSchema.table.insert(
            or: .replace,
            NodesSchema.key <- key,
            NodesSchema.checksum <- checksum,
            NodesSchema.createdAt <- Date()
        ))
    }

    public func node(for key: String) throws -> String? {
        try db.pluck(
            NodesSchema.table
                .select(NodesSchema.checksum)
                .filter(NodesSchema.key == key)
        )?[NodesSchema.checksum]
    }

    // MARK: - KeyValue Metadata

    public func storeKeyValueMetadata(key: String, operationType: String, duration: TimeInterval) throws {
        try db.run(KeyValueMetadataSchema.table.insert(
            or: .replace,
            KeyValueMetadataSchema.key <- key,
            KeyValueMetadataSchema.operationType <- operationType,
            KeyValueMetadataSchema.duration <- duration,
            KeyValueMetadataSchema.createdAt <- Date()
        ))
    }

    public func keyValueMetadata(for key: String, operationType: String) throws -> KeyValueMetadata? {
        guard let row = try db.pluck(
            KeyValueMetadataSchema.table
                .filter(KeyValueMetadataSchema.key == key && KeyValueMetadataSchema.operationType == operationType)
        ) else { return nil }
        return KeyValueMetadata(duration: row[KeyValueMetadataSchema.duration])
    }

    // MARK: - Maintenance

    public func removeOldEntries(olderThan date: Date) throws {
        try db.run(CASOutputsSchema.table.filter(CASOutputsSchema.createdAt < date).delete())
        try db.run(NodesSchema.table.filter(NodesSchema.createdAt < date).delete())
        try db.run(KeyValueMetadataSchema.table.filter(KeyValueMetadataSchema.createdAt < date).delete())
    }
}
