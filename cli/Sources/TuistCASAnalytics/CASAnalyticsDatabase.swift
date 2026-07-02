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
    func storeCASOutput(
        key: String,
        size: Int,
        duration: TimeInterval,
        compressedSize: Int,
        transferDuration: TimeInterval,
        codecDuration: TimeInterval
    ) throws
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
    private let writer: BufferedWriter

    public init() throws {
        db = try Connection(
            Environment.current.stateDirectory.appending(component: Self.databaseName).pathString
        )
        db.busyTimeout = 5
        // This database is disposable per-build analytics. Writes are buffered
        // in memory and persisted in batched transactions from a dedicated GCD
        // queue (see BufferedWriter): the store methods run once per CAS
        // operation in the daemon, and any synchronous SQLite work there blocks
        // a Swift-concurrency cooperative-pool thread. Under a build's disk
        // contention those blocked threads starved the daemon's fetch
        // continuations, inflating every cache operation (~150ms/op measured
        // on runner VMs). synchronous=OFF drops the per-commit fsync
        // (durability isn't needed here). The main db file stays current for
        // the build-report upload via a passive WAL checkpoint after each
        // batch flush plus a truncating checkpoint on the uploader side before
        // it copies the file.
        try db.execute("PRAGMA synchronous = OFF")
        writer = BufferedWriter(db: db)
    }

    /// Folds the WAL into the main database file so a plain file copy of
    /// `cas_analytics.db` observes every row flushed so far. Used by the
    /// build-report upload, which copies the `.db` file, not the WAL.
    public static func checkpoint(at path: AbsolutePath) throws {
        let db = try Connection(path.pathString)
        db.busyTimeout = 5
        try db.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    }

    public func migrate() throws {
        try db.execute("PRAGMA journal_mode = WAL")
        try db.run(CASOutputsSchema.table.create(ifNotExists: true) { t in
            t.column(CASOutputsSchema.key, primaryKey: true)
            t.column(CASOutputsSchema.size)
            t.column(CASOutputsSchema.duration)
            t.column(CASOutputsSchema.compressedSize)
            t.column(CASOutputsSchema.createdAt, defaultValue: Date())
            t.column(CASOutputsSchema.transferDuration, defaultValue: 0)
            t.column(CASOutputsSchema.codecDuration, defaultValue: 0)
        })
        for column in [CASOutputsSchema.transferDuration, CASOutputsSchema.codecDuration] {
            try? db.run(CASOutputsSchema.table.addColumn(column, defaultValue: 0))
        }

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

    public func storeCASOutput(
        key: String,
        size: Int,
        duration: TimeInterval,
        compressedSize: Int,
        transferDuration: TimeInterval,
        codecDuration: TimeInterval
    ) throws {
        writer.enqueue(.casOutput(
            key: key,
            size: size,
            duration: duration,
            compressedSize: compressedSize,
            transferDuration: transferDuration,
            codecDuration: codecDuration,
            createdAt: Date()
        ))
    }

    public func casOutput(for key: String) throws -> CASOutputMetadata? {
        writer.flushSync()
        guard let row = try db.pluck(
            CASOutputsSchema.table.filter(CASOutputsSchema.key == key)
        ) else { return nil }
        return CASOutputMetadata(
            size: row[CASOutputsSchema.size],
            duration: row[CASOutputsSchema.duration],
            compressedSize: row[CASOutputsSchema.compressedSize],
            transferDuration: row[CASOutputsSchema.transferDuration],
            codecDuration: row[CASOutputsSchema.codecDuration]
        )
    }

    // MARK: - Nodes

    public func storeNode(key: String, checksum: String) throws {
        writer.enqueue(.node(key: key, checksum: checksum, createdAt: Date()))
    }

    public func node(for key: String) throws -> String? {
        writer.flushSync()
        return try db.pluck(
            NodesSchema.table
                .select(NodesSchema.checksum)
                .filter(NodesSchema.key == key)
        )?[NodesSchema.checksum]
    }

    // MARK: - KeyValue Metadata

    public func storeKeyValueMetadata(key: String, operationType: String, duration: TimeInterval) throws {
        writer.enqueue(.keyValueMetadata(
            key: key,
            operationType: operationType,
            duration: duration,
            createdAt: Date()
        ))
    }

    public func keyValueMetadata(for key: String, operationType: String) throws -> KeyValueMetadata? {
        writer.flushSync()
        guard let row = try db.pluck(
            KeyValueMetadataSchema.table
                .filter(KeyValueMetadataSchema.key == key && KeyValueMetadataSchema.operationType == operationType)
        ) else { return nil }
        return KeyValueMetadata(duration: row[KeyValueMetadataSchema.duration])
    }

    // MARK: - Maintenance

    public func removeOldEntries(olderThan date: Date) throws {
        writer.flushSync()
        try db.run(CASOutputsSchema.table.filter(CASOutputsSchema.createdAt < date).delete())
        try db.run(NodesSchema.table.filter(NodesSchema.createdAt < date).delete())
        try db.run(KeyValueMetadataSchema.table.filter(KeyValueMetadataSchema.createdAt < date).delete())
    }
}

// MARK: - BufferedWriter

/// Buffers analytics rows in memory and persists them in batched transactions
/// from a dedicated GCD queue, so the store methods never do SQLite work on
/// the caller's thread (and never block a cooperative-pool thread). A periodic
/// flush bounds how stale the on-disk database can get, and a passive WAL
/// checkpoint after each flush keeps the main db file current for the
/// build-report upload's plain file copy.
private final class BufferedWriter: @unchecked Sendable {
    enum Row {
        case casOutput(
            key: String,
            size: Int,
            duration: TimeInterval,
            compressedSize: Int,
            transferDuration: TimeInterval,
            codecDuration: TimeInterval,
            createdAt: Date
        )
        case node(key: String, checksum: String, createdAt: Date)
        case keyValueMetadata(key: String, operationType: String, duration: TimeInterval, createdAt: Date)
    }

    private static let flushThreshold = 128
    private static let flushInterval: TimeInterval = 1

    private let db: Connection
    private let queue = DispatchQueue(label: "dev.tuist.cas-analytics-flush", qos: .utility)
    private let lock = NSLock()
    private var pending: [Row] = []
    private let timer: DispatchSourceTimer

    init(db: Connection) {
        self.db = db
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.flushInterval, repeating: Self.flushInterval)
        timer.setEventHandler { [weak self] in
            self?.flushOnQueue()
        }
        timer.activate()
    }

    deinit {
        timer.cancel()
        flushOnQueue()
    }

    func enqueue(_ row: Row) {
        var drained: [Row] = []
        lock.lock()
        pending.append(row)
        if pending.count >= Self.flushThreshold {
            drained = pending
            pending = []
        }
        lock.unlock()
        if !drained.isEmpty {
            queue.async { [weak self] in
                self?.write(drained)
            }
        }
    }

    /// Drains and persists synchronously. Used before reads (read-after-write
    /// consistency for consumers and tests) and on deinit.
    func flushSync() {
        queue.sync {
            self.flushOnQueue()
        }
    }

    private func flushOnQueue() {
        lock.lock()
        let drained = pending
        pending = []
        lock.unlock()
        write(drained)
    }

    private func write(_ rows: [Row]) {
        guard !rows.isEmpty else { return }
        // Disposable analytics: a failed batch is dropped rather than allowed
        // to disturb the daemon's request handling.
        try? db.transaction {
            for row in rows {
                switch row {
                case let .casOutput(key, size, duration, compressedSize, transferDuration, codecDuration, createdAt):
                    try db.run(CASOutputsSchema.table.insert(
                        or: .replace,
                        CASOutputsSchema.key <- key,
                        CASOutputsSchema.size <- size,
                        CASOutputsSchema.duration <- duration,
                        CASOutputsSchema.compressedSize <- compressedSize,
                        CASOutputsSchema.createdAt <- createdAt,
                        CASOutputsSchema.transferDuration <- transferDuration,
                        CASOutputsSchema.codecDuration <- codecDuration
                    ))
                case let .node(key, checksum, createdAt):
                    try db.run(NodesSchema.table.insert(
                        or: .replace,
                        NodesSchema.key <- key,
                        NodesSchema.checksum <- checksum,
                        NodesSchema.createdAt <- createdAt
                    ))
                case let .keyValueMetadata(key, operationType, duration, createdAt):
                    try db.run(KeyValueMetadataSchema.table.insert(
                        or: .replace,
                        KeyValueMetadataSchema.key <- key,
                        KeyValueMetadataSchema.operationType <- operationType,
                        KeyValueMetadataSchema.duration <- duration,
                        KeyValueMetadataSchema.createdAt <- createdAt
                    ))
                }
            }
        }
        try? db.execute("PRAGMA wal_checkpoint(PASSIVE)")
    }
}
