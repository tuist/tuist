import CASAnalyticsDatabase // re-exports SQLite
import Foundation
import Mockable
import Path
import Synchronization
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
    )
    func casOutput(for key: String) async throws -> CASOutputMetadata?

    func storeNode(key: String, checksum: String)
    func node(for key: String) async throws -> String?

    func storeKeyValueMetadata(key: String, operationType: String, duration: TimeInterval)
    func keyValueMetadata(for key: String, operationType: String) async throws -> KeyValueMetadata?

    func migrate() async throws
    func removeOldEntries(olderThan: Date) async throws
}

/// Thin facade over an actor that owns the SQLite connection.
///
/// The cache proxy performs the per-operation analytics writes; this Swift type
/// owns the canonical schema (`migrate`) that the proxy writes into and the
/// server reads, plus the WAL checkpoint the build-report upload relies on. The
/// store methods are synchronous fire-and-forget appends: rows buffer in the
/// actor and are persisted in batched transactions. The actor runs on its own
/// dispatch-queue executor, so SQLite work never occupies a Swift-concurrency
/// cooperative-pool thread, which under a build's disk contention would starve
/// the writer's fetch continuations and inflate every cache operation.
public struct CASAnalyticsDatabase: CASAnalyticsDatabasing {
    public static let databaseName = "cas_analytics.db"

    private let writer: Writer

    public init() throws {
        writer = try Writer(
            path: Environment.current.stateDirectory.appending(component: Self.databaseName).pathString
        )
    }

    /// Folds the WAL into the main database file so a plain file copy of
    /// `cas_analytics.db` observes every row flushed so far. Used by the
    /// build-report upload, which copies the `.db` file, not the WAL.
    public static func checkpoint(at path: AbsolutePath) throws {
        let db = try Connection(path.pathString)
        db.busyTimeout = 5
        try db.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    }

    public func migrate() async throws {
        try await writer.migrate()
    }

    // MARK: - CAS Outputs

    public func storeCASOutput(
        key: String,
        size: Int,
        duration: TimeInterval,
        compressedSize: Int,
        transferDuration: TimeInterval,
        codecDuration: TimeInterval
    ) {
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

    public func casOutput(for key: String) async throws -> CASOutputMetadata? {
        try await writer.casOutput(for: key)
    }

    // MARK: - Nodes

    public func storeNode(key: String, checksum: String) {
        writer.enqueue(.node(key: key, checksum: checksum, createdAt: Date()))
    }

    public func node(for key: String) async throws -> String? {
        try await writer.node(for: key)
    }

    // MARK: - KeyValue Metadata

    public func storeKeyValueMetadata(key: String, operationType: String, duration: TimeInterval) {
        writer.enqueue(.keyValueMetadata(
            key: key,
            operationType: operationType,
            duration: duration,
            createdAt: Date()
        ))
    }

    public func keyValueMetadata(for key: String, operationType: String) async throws -> KeyValueMetadata? {
        try await writer.keyValueMetadata(for: key, operationType: operationType)
    }

    // MARK: - Maintenance

    public func removeOldEntries(olderThan date: Date) async throws {
        try await writer.removeOldEntries(olderThan: date)
    }
}

// MARK: - Writer

/// Owns the SQLite connection and buffers analytics rows, persisting them in
/// batched transactions. The actor's jobs run on a dedicated dispatch-queue
/// executor, so a stalled write (contended disk) never occupies a
/// cooperative-pool thread; `enqueue` is nonisolated fire-and-forget so the
/// recording side never waits either. A periodic flush bounds how stale the
/// on-disk database can get, and a passive WAL checkpoint after each flush
/// keeps the main db file current for the build-report upload's plain file
/// copy. Reads flush first, preserving read-after-write for consumers and
/// tests.
private actor Writer {
    enum Row: Sendable {
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

    private struct Buffer {
        var rows: [Row] = []
        var flusherStarted = false
    }

    private static let flushThreshold = 128
    private static let flushInterval: Duration = .seconds(1)

    private let db: Connection
    private let executorQueue: DispatchSerialQueue
    /// The enqueue buffer lives outside actor isolation so recording stays a
    /// synchronous, guaranteed-visible append: a read that follows a store
    /// always drains the row (the actor mailbox offers no such ordering for
    /// a task-per-enqueue design).
    private nonisolated let buffer = Mutex(Buffer())
    private var periodicFlusher: Task<Void, Never>?

    nonisolated var unownedExecutor: UnownedSerialExecutor {
        executorQueue.asUnownedSerialExecutor()
    }

    init(path: String) throws {
        executorQueue = DispatchSerialQueue(label: "dev.tuist.cas-analytics", qos: .utility)
        db = try Connection(path)
        db.busyTimeout = 5
        // Disposable per-build analytics: synchronous=OFF drops the per-commit
        // fsync. Durability is bounded by the batched flushes instead.
        try db.execute("PRAGMA synchronous = OFF")
    }

    deinit {
        periodicFlusher?.cancel()
    }

    nonisolated func enqueue(_ row: Row) {
        // The recording side never waits, even while a flush is stalled on a
        // contended disk: the append is a mutex-guarded array push, and flush
        // work is scheduled at most once per threshold crossing.
        let (startFlusher, crossedThreshold) = buffer.withLock { buffer in
            buffer.rows.append(row)
            let startFlusher = !buffer.flusherStarted
            buffer.flusherStarted = true
            return (startFlusher, buffer.rows.count == Self.flushThreshold)
        }
        if startFlusher {
            Task { await self.startPeriodicFlusher() }
        }
        if crossedThreshold {
            Task { await self.flush() }
        }
    }

    private func startPeriodicFlusher() {
        guard periodicFlusher == nil else { return }
        periodicFlusher = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.flushInterval)
                await self?.flush()
            }
        }
    }

    private func flush() {
        let rows = buffer.withLock { buffer in
            let rows = buffer.rows
            buffer.rows = []
            return rows
        }
        guard !rows.isEmpty else { return }
        // Runs on the actor's dispatch-queue executor, not the cooperative
        // pool. Disposable analytics: a failed batch is dropped rather than
        // surfaced to the caller.
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

    func migrate() throws {
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

    func casOutput(for key: String) throws -> CASOutputMetadata? {
        flush()
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

    func node(for key: String) throws -> String? {
        flush()
        return try db.pluck(
            NodesSchema.table
                .select(NodesSchema.checksum)
                .filter(NodesSchema.key == key)
        )?[NodesSchema.checksum]
    }

    func keyValueMetadata(for key: String, operationType: String) throws -> KeyValueMetadata? {
        flush()
        guard let row = try db.pluck(
            KeyValueMetadataSchema.table
                .filter(KeyValueMetadataSchema.key == key && KeyValueMetadataSchema.operationType == operationType)
        ) else { return nil }
        return KeyValueMetadata(duration: row[KeyValueMetadataSchema.duration])
    }

    func removeOldEntries(olderThan date: Date) throws {
        flush()
        try db.run(CASOutputsSchema.table.filter(CASOutputsSchema.createdAt < date).delete())
        try db.run(NodesSchema.table.filter(NodesSchema.createdAt < date).delete())
        try db.run(KeyValueMetadataSchema.table.filter(KeyValueMetadataSchema.createdAt < date).delete())
    }
}
