#if canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#elseif canImport(Darwin)
    import Darwin.C
#endif
import Foundation
import Mockable
import OpenAPIRuntime
import TuistHTTP

#if !os(iOS)
    import TuistEnvironment
    import TuistLogging
#endif

/// The report creations the server deduplicates by the client-supplied `id`, so a queued request can be sent again.
public enum ReportOutboxOperation: String, Codable, Sendable {
    case commandEvent = "command_event"
    case testRun = "test_run"

    var operationID: String {
        switch self {
        case .commandEvent: "createCommandEvent"
        case .testRun: "createTest"
        }
    }
}

struct ReportOutboxEntry: Codable, Equatable, Sendable {
    let operation: ReportOutboxOperation
    let id: String
    let fullHandle: String
    let serverURL: URL
    let createdAt: Date
}

/// A report rejected or answered by the server with a status other than success.
struct ReportResponseError: LocalizedError, HTTPStatusCodeError {
    let message: String
    let httpStatusCode: Int

    var errorDescription: String? { message }
}

/// Tracks one report request through the client, so the outbox learns whether it left with credentials.
final class ReportOutboxSend: @unchecked Sendable {
    @TaskLocal static var current: ReportOutboxSend?

    private let operationID: String
    private let onFirstCredentialedSend: @Sendable () -> Void
    private let lock = NSLock()
    private var credentialed = false

    init(operationID: String, onFirstCredentialedSend: @escaping @Sendable () -> Void = {}) {
        self.operationID = operationID
        self.onFirstCredentialedSend = onFirstCredentialedSend
    }

    var sentWithCredentials: Bool {
        lock.withLock { credentialed }
    }

    func willSendWithCredentials(operationID: String) {
        guard operationID == self.operationID else { return }
        let isFirst = lock.withLock {
            defer { credentialed = true }
            return !credentialed
        }
        if isFirst { onFirstCredentialedSend() }
    }
}

@Mockable
public protocol ReportOutboxing: Sendable {
    func hasPendingEntries() -> Bool
    func flush() async
}

/// Keeps report creations the server deduplicates by id on disk until the server answers them, so a report whose
/// upload fails, times out or is cut short by the process exiting is sent again later with the same id and body.
///
/// An entry is written when the request first leaves with credentials, and removed once the server accepts it or
/// rejects it with a 4xx other than 408 and 429. Entries older than `maximumAge` are dropped unsent, because the
/// server forgets the ids it deduplicated an hour after it saw them. Outbox failures are logged and never surface.
public struct ReportOutbox: ReportOutboxing {
    static let maximumAge: TimeInterval = 45 * 60
    static let maximumEntryCount = 100
    static let maximumTotalBytes = 50 * 1024 * 1024
    private static let entryExtension = "entry"
    private static let temporaryExtension = "tmp"

    private let directory: URL?
    private let now: @Sendable () -> Date

    public init() {
        #if os(iOS)
            self.init(directory: nil)
        #else
            self.init(
                directory: URL(
                    fileURLWithPath: Environment.current.stateDirectory.appending(component: "report-outbox").pathString
                )
            )
        #endif
    }

    init(directory: URL?, now: @escaping @Sendable () -> Date = { Date() }) {
        self.directory = directory
        self.now = now
    }

    /// Sends a report through `send`, keeping it in the outbox while the server has not answered it.
    func deliver<Result>(
        _ operation: ReportOutboxOperation,
        id: String?,
        fullHandle: String,
        serverURL: URL,
        body: some Encodable & Sendable,
        send: () async throws -> Result
    ) async throws -> Result {
        guard let directory, let id, UUID(uuidString: id) != nil else { return try await send() }
        let entry = ReportOutboxEntry(
            operation: operation,
            id: id.lowercased(),
            fullHandle: fullHandle,
            serverURL: serverURL,
            createdAt: now()
        )
        let file = directory.appendingPathComponent(Self.fileName(for: entry))
        let reportSend = ReportOutboxSend(operationID: operation.operationID) {
            write(entry, body: body, to: file, in: directory)
        }
        do {
            let result = try await ReportOutboxSend.$current.withValue(reportSend) { try await send() }
            if reportSend.sentWithCredentials { remove(file) }
            return result
        } catch {
            if reportSend.sentWithCredentials, Self.isPermanentRejection(error) { remove(file) }
            throw error
        }
    }

    public func hasPendingEntries() -> Bool {
        guard let directory,
              let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        else { return false }
        return names.contains { $0.hasSuffix(".\(Self.entryExtension)") }
    }

    /// Sends pending entries again, oldest first, with the current credentials for each entry's server. The pass
    /// stops at the first failure that could be transient. An entry without credentials to send it is kept.
    public func flush() async {
        for file in pendingFiles() {
            guard let contents = try? Data(contentsOf: file) else { continue }
            guard let decoded = Self.decode(contents),
                  now().timeIntervalSince(decoded.entry.createdAt) <= Self.maximumAge
            else {
                remove(file)
                continue
            }
            let (entry, body) = decoded
            let reportSend = ReportOutboxSend(operationID: entry.operation.operationID)
            do {
                try await ReportOutboxSend.$current.withValue(reportSend) { try await Self.replay(entry, body: body) }
                remove(file)
            } catch is DecodingError {
                remove(file)
            } catch {
                guard reportSend.sentWithCredentials else {
                    debug("Kept report \(entry.id) in the outbox, no credentials to send it: \(error)")
                    continue
                }
                if Self.isPermanentRejection(error) {
                    remove(file)
                    continue
                }
                debug("Stopped sending reports from the outbox: \(error)")
                return
            }
        }
    }

    /// Entries oldest first, after removing expired and corrupt ones and the oldest ones beyond the bounds.
    func pendingFiles() -> [URL] {
        guard let directory,
              let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        else { return [] }
        let now = now()
        var entries: [PendingFile] = []
        for name in names {
            let file = directory.appendingPathComponent(name)
            if name.hasSuffix(".\(Self.temporaryExtension)") {
                if let modified = Self.attributes(of: file)?[.modificationDate] as? Date,
                   now.timeIntervalSince(modified) > Self.maximumAge
                {
                    remove(file)
                }
                continue
            }
            guard name.hasSuffix(".\(Self.entryExtension)") else { continue }
            guard let createdAt = Self.creationDate(fromFileName: name),
                  now.timeIntervalSince(createdAt) <= Self.maximumAge
            else {
                remove(file)
                continue
            }
            let size = (Self.attributes(of: file)?[.size] as? NSNumber)?.intValue ?? 0
            entries.append(PendingFile(file: file, createdAt: createdAt, size: size))
        }
        entries.sort { $0.createdAt == $1.createdAt ? $0.file.path < $1.file.path : $0.createdAt < $1.createdAt }
        var totalBytes = entries.reduce(0) { $0 + $1.size }
        while entries.count > Self.maximumEntryCount || totalBytes > Self.maximumTotalBytes, let oldest = entries.first {
            remove(oldest.file)
            totalBytes -= oldest.size
            entries.removeFirst()
        }
        return entries.map(\.file)
    }

    private struct PendingFile {
        let file: URL
        let createdAt: Date
        let size: Int
    }

    private func write(_ entry: ReportOutboxEntry, body: some Encodable, to file: URL, in directory: URL) {
        do {
            let header = try JSONEncoder().encode(entry)
            let body = try JSONEncoder().encode(body)
            guard header.count + body.count + 1 <= Self.maximumTotalBytes else {
                debug("Not keeping report \(entry.id) in the outbox: \(body.count) bytes is above its bound")
                return
            }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let temporaryFile = directory.appendingPathComponent(".\(UUID().uuidString).\(Self.temporaryExtension)")
            try (header + Data("\n".utf8) + body).write(to: temporaryFile)
            guard rename(temporaryFile.path, file.path) == 0 else {
                let error = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                remove(temporaryFile)
                throw error
            }
            _ = pendingFiles()
        } catch {
            debug("Failed to keep report \(entry.id) in the outbox: \(error)")
        }
    }

    private func remove(_ file: URL) {
        do {
            try FileManager.default.removeItem(at: file)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return
        } catch {
            debug("Failed to remove \(file.lastPathComponent) from the report outbox: \(error)")
        }
    }

    private func debug(_ message: String) {
        #if !os(iOS)
            Logger.current.debug("\(message)")
        #endif
    }

    static func fileName(for entry: ReportOutboxEntry) -> String {
        let milliseconds = Int64(entry.createdAt.timeIntervalSince1970 * 1000)
        return "\(milliseconds)-\(entry.operation.rawValue)-\(entry.id).\(entryExtension)"
    }

    private static func creationDate(fromFileName name: String) -> Date? {
        guard let milliseconds = name.split(separator: "-", maxSplits: 1).first.flatMap({ Int64($0) }) else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
    }

    private static func attributes(of file: URL) -> [FileAttributeKey: Any]? {
        try? FileManager.default.attributesOfItem(atPath: file.path)
    }

    static func decode(_ contents: Data) -> (entry: ReportOutboxEntry, body: Data)? {
        guard let newline = contents.firstIndex(of: UInt8(ascii: "\n")),
              let entry = try? JSONDecoder().decode(ReportOutboxEntry.self, from: contents[contents.startIndex ..< newline])
        else { return nil }
        return (entry, Data(contents[contents.index(after: newline)...]))
    }

    /// The server answered and will answer a repeated request the same way.
    static func isPermanentRejection(_ error: any Error) -> Bool {
        switch error {
        case let error as any HTTPStatusCodeError:
            return HTTPRetryPolicy.isPermanentClientError(statusCode: error.httpStatusCode)
        case let error as ClientError:
            return isPermanentRejection(error.underlyingError)
        default:
            return false
        }
    }

    private static func replay(_ entry: ReportOutboxEntry, body: Data) async throws {
        let decoder = JSONDecoder()
        switch entry.operation {
        case .commandEvent:
            let payload = try decoder.decode(Operations.createCommandEvent.Input.Body.jsonPayload.self, from: body)
            let config = ServerAuthenticationConfig.current
            let response = try await ServerAuthenticationConfig.$current.withValue(
                .init(backgroundRefresh: config.backgroundRefresh, optionalAuthentication: false)
            ) {
                try await Client.authenticated(serverURL: entry.serverURL).createCommandEvent(
                    query: .init(project_id: entry.fullHandle),
                    body: .json(payload)
                )
            }
            try check(statusCode(of: response), entry: entry)
        case .testRun:
            let payload = try decoder.decode(Operations.createTest.Input.Body.jsonPayload.self, from: body)
            let handles = try FullHandleService().parse(entry.fullHandle)
            let response = try await Client.reporting(serverURL: entry.serverURL, networkTrusted: false).createTest(
                path: .init(account_handle: handles.accountHandle, project_handle: handles.projectHandle),
                body: .json(payload)
            )
            try check(statusCode(of: response), entry: entry)
        }
    }

    private static func check(_ statusCode: Int, entry: ReportOutboxEntry) throws {
        guard !(200 ..< 300).contains(statusCode) else { return }
        throw ReportResponseError(
            message: "The server answered report \(entry.id) with status \(statusCode).",
            httpStatusCode: statusCode
        )
    }

    static func statusCode(of output: Operations.createCommandEvent.Output) -> Int {
        switch output {
        case .ok: 200
        case .unauthorized: 401
        case .forbidden: 403
        case .tooManyRequests: 429
        case let .undocumented(statusCode, _): statusCode
        }
    }

    static func statusCode(of output: Operations.createTest.Output) -> Int {
        switch output {
        case .ok: 200
        case .badRequest: 400
        case .unauthorized: 401
        case .forbidden: 403
        case .notFound: 404
        case .tooManyRequests: 429
        case .serviceUnavailable: 503
        case let .undocumented(statusCode, _): statusCode
        }
    }
}
