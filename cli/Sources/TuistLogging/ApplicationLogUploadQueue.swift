#if !os(Linux)
    import Foundation

    public struct ApplicationLogEntry: Codable, Equatable, Sendable {
        public let timestamp: Date
        public let level: Logger.Level
        public let source: String
        public let message: String
        public let launchID: String

        public init(timestamp: Date, level: Logger.Level, source: String, message: String, launchID: String) {
            self.timestamp = timestamp
            self.level = level
            self.source = source
            self.message = message
            self.launchID = launchID
        }
    }

    public struct ApplicationLogBatch: Equatable, Sendable {
        public let id: String
        public let entries: [ApplicationLogEntry]

        public init(id: String, entries: [ApplicationLogEntry]) {
            self.id = id
            self.entries = entries
        }
    }

    public protocol ApplicationLogUploadQueuing: Sendable {
        func append(_ entry: ApplicationLogEntry)
        func seal() async
        func nextBatch() async -> ApplicationLogBatch?
        func remove(_ batch: ApplicationLogBatch) async
    }

    /// Persists log entries waiting to be uploaded, grouped into batch files that survive app launches.
    ///
    /// Entries are appended to a pending file. Once it holds `maximumBatchEntries` entries or `maximumBatchSize` bytes,
    /// or when `seal()` is called, it becomes a batch file. Only the newest `maximumBatchCount` batches are kept, and
    /// batches older than `maximumAge` are dropped, so logs from a device that cannot upload stay bounded.
    public final class ApplicationLogUploadQueue: ApplicationLogUploadQueuing, @unchecked Sendable {
        @TaskLocal public static var current: any ApplicationLogUploadQueuing = ApplicationLogUploadQueue()

        static let maximumMessageLength = 8000
        private static let maximumBatchEntries = 500
        private static let maximumBatchSize = 1_000_000
        private static let maximumBatchCount = 5
        private static let maximumAge: TimeInterval = 3 * 24 * 60 * 60

        private let directory: URL
        private let queue = DispatchQueue(label: "dev.tuist.logging.upload-queue")
        private let encoder: JSONEncoder
        private let decoder: JSONDecoder
        private var pendingHandle: FileHandle?
        private var pendingEntryCount = 0
        private var pendingSize = 0
        private var batchSequence = 0

        public convenience init() {
            self.init(directory: Self.defaultDirectory)
        }

        init(directory: URL) {
            self.directory = directory
            encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            queue.async { self.sealPending() }
        }

        public func append(_ entry: ApplicationLogEntry) {
            queue.async {
                self.write(Self.truncated(entry))
            }
        }

        public func seal() async {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                queue.async {
                    self.sealPending()
                    continuation.resume()
                }
            }
        }

        public func nextBatch() async -> ApplicationLogBatch? {
            await withCheckedContinuation { continuation in
                queue.async {
                    continuation.resume(returning: self.oldestBatch())
                }
            }
        }

        public func remove(_ batch: ApplicationLogBatch) async {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                queue.async {
                    try? FileManager.default.removeItem(at: self.directory.appendingPathComponent(batch.id))
                    continuation.resume()
                }
            }
        }

        private var pendingURL: URL {
            directory.appendingPathComponent("pending.jsonl")
        }

        private func write(_ entry: ApplicationLogEntry) {
            guard var data = try? encoder.encode(entry) else { return }
            data.append(Data("\n".utf8))
            do {
                let handle = try openPendingHandle()
                try handle.write(contentsOf: data)
                pendingEntryCount += 1
                pendingSize += data.count
            } catch {
                return
            }
            if pendingEntryCount >= Self.maximumBatchEntries || pendingSize >= Self.maximumBatchSize {
                sealPending()
            }
        }

        private func openPendingHandle() throws -> FileHandle {
            if let pendingHandle { return pendingHandle }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            var directory = directory
            try? directory.setResourceValues(resourceValues)
            if !FileManager.default.fileExists(atPath: pendingURL.path) {
                FileManager.default.createFile(atPath: pendingURL.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: pendingURL)
            try handle.seekToEnd()
            pendingHandle = handle
            return handle
        }

        private func sealPending() {
            try? pendingHandle?.close()
            pendingHandle = nil
            pendingEntryCount = 0
            pendingSize = 0

            let size = (try? FileManager.default.attributesOfItem(atPath: pendingURL.path)[.size] as? NSNumber)?
                .intValue ?? 0
            if size > 0 {
                batchSequence += 1
                let batchName =
                    "batch-\(Self.sortableTimestamp(Date()))-\(String(format: "%06d", batchSequence))-\(UUID().uuidString).jsonl"
                try? FileManager.default.moveItem(at: pendingURL, to: directory.appendingPathComponent(batchName))
            }
            pruneBatches()
        }

        private func batchFiles() -> [URL] {
            let files = (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey]
            )) ?? []
            return files
                .filter { $0.lastPathComponent.hasPrefix("batch-") && $0.pathExtension == "jsonl" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        }

        private func pruneBatches() {
            let cutoffDate = Date().addingTimeInterval(-Self.maximumAge)
            var batches = batchFiles()
            for batch in batches {
                let modificationDate = (try? batch.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                if modificationDate < cutoffDate {
                    try? FileManager.default.removeItem(at: batch)
                }
            }
            batches = batchFiles()
            for batch in batches.dropLast(Self.maximumBatchCount) {
                try? FileManager.default.removeItem(at: batch)
            }
        }

        private func oldestBatch() -> ApplicationLogBatch? {
            for batch in batchFiles() {
                let entries = (try? String(contentsOf: batch, encoding: .utf8))?
                    .split(separator: "\n")
                    .compactMap { try? decoder.decode(ApplicationLogEntry.self, from: Data($0.utf8)) } ?? []
                if entries.isEmpty {
                    try? FileManager.default.removeItem(at: batch)
                    continue
                }
                return ApplicationLogBatch(id: batch.lastPathComponent, entries: entries)
            }
            return nil
        }

        private static func truncated(_ entry: ApplicationLogEntry) -> ApplicationLogEntry {
            ApplicationLogEntry(
                timestamp: entry.timestamp,
                level: entry.level,
                source: String(entry.source.prefix(256)),
                message: String(entry.message.prefix(maximumMessageLength)),
                launchID: entry.launchID
            )
        }

        private static func sortableTimestamp(_ date: Date) -> String {
            String(format: "%015.3f", date.timeIntervalSince1970)
        }

        private static var defaultDirectory: URL {
            URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library")
                .appendingPathComponent("Application Support")
                .appendingPathComponent(Bundle.main.bundleIdentifier ?? "dev.tuist.app")
                .appendingPathComponent("LogUploads")
        }
    }

    /// Sends redacted log lines to the upload queue so the app can ship them to the Tuist server.
    public struct ApplicationLogUploadLogHandler: LogHandler {
        private let launchID: String
        private let queue: any ApplicationLogUploadQueuing
        private let lineTransformer: @Sendable (String) -> String
        private let shouldLog: @Sendable (Logger.Level, Logger.Message, String) -> Bool
        public var metadata: Logger.Metadata = [:]
        public var logLevel: Logger.Level = .debug

        public init(
            launchID: String,
            queue: any ApplicationLogUploadQueuing,
            lineTransformer: @escaping @Sendable (String) -> String,
            shouldLog: @escaping @Sendable (Logger.Level, Logger.Message, String) -> Bool = { _, _, _ in true }
        ) {
            self.launchID = launchID
            self.queue = queue
            self.lineTransformer = lineTransformer
            self.shouldLog = shouldLog
        }

        public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
            get { metadata[key] }
            set { metadata[key] = newValue }
        }

        public func log(
            level: Logger.Level,
            message: Logger.Message,
            metadata: Logger.Metadata?,
            source: String,
            file _: String,
            function _: String,
            line _: UInt
        ) {
            guard shouldLog(level, message, source) else { return }
            let mergedMetadata = self.metadata.merging(metadata ?? [:]) { _, new in new }
            let metadataString = mergedMetadata.isEmpty ? "" : " \(mergedMetadata)"
            queue.append(
                ApplicationLogEntry(
                    timestamp: Date(),
                    level: level,
                    source: source,
                    message: lineTransformer("\(message)\(metadataString)"),
                    launchID: launchID
                )
            )
        }
    }
#endif
