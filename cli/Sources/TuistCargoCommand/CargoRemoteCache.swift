import Foundation
import TuistREAPI
#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#endif

/// A command-session relay. Admission, artifact validation, and ownership of blob files remain with the compiler.
struct CargoRemoteCache: REAPICacheStoring, Sendable {
    static let metadataTimeout: Duration = .seconds(1)

    struct Timing: Sendable {
        let now: @Sendable () -> ContinuousClock.Instant
        let sleep: @Sendable (Duration) async throws -> Void
    }

    @TaskLocal static var timing = Timing(now: { .now }, sleep: { try await Task.sleep(for: $0) })

    private let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    static func isOverloaded(_ error: Error) -> Bool {
        guard let error = error as? BrokerError else { return false }
        if case .busy = error { return true }
        return false
    }

    func actionResult(for digest: REAPI.Digest) async throws -> REAPI.ActionResult? {
        let response = try await call(Request(operation: .actionResult, digest: digest.serializedData()))
        return try response.result.map { try REAPI.ActionResult(serializedBytes: $0) }
    }

    func containsActionResult(for digest: REAPI.Digest) async throws -> Bool {
        let response = try await call(Request(operation: .containsActionResult, digest: digest.serializedData()))
        guard let contains = response.contains else { throw BrokerError.invalidMessage }
        return contains
    }

    func storeActionResult(_ result: REAPI.ActionResult, for digest: REAPI.Digest) async throws {
        _ = try await call(Request(
            operation: .storeActionResult,
            digest: digest.serializedData(),
            result: result.serializedData()
        ))
    }

    func uploadAvailableBlobs(_ blobs: [REAPI.Digest: URL]) async throws -> REAPIBlobUpload {
        let response = try await call(Request(operation: .uploadAvailableBlobs, blobs: Self.encode(blobs)))
        var failures: [REAPI.Digest: String] = [:]
        for failure in response.failures {
            let digest = try CargoCacheIPC.digest(failure.digest)
            guard blobs[digest] != nil, failures[digest] == nil else { throw BrokerError.invalidMessage }
            failures[digest] = failure.reason
        }
        return try REAPIBlobUpload(
            available: Self.digests(response.available, within: blobs),
            failures: failures,
            uploaded: response.uploaded.map { try Self.digests($0, within: blobs) }
        )
    }

    func downloadAvailableBlobs(_ blobs: [REAPI.Digest: URL]) async throws -> Set<REAPI.Digest> {
        try await downloadBlobs(blobs).available
    }

    func downloadBlobs(_ blobs: [REAPI.Digest: URL]) async throws -> REAPIBlobDownload {
        let response = try await call(Request(operation: .downloadAvailableBlobs, blobs: Self.encode(blobs)))
        let available = try Self.digests(response.available, within: blobs)
        let failures = try Self.digests(response.remoteFailures ?? [], within: blobs)
        guard available.isDisjoint(with: failures) else { throw BrokerError.invalidMessage }
        return REAPIBlobDownload(available: available, remoteFailures: failures)
    }

    func uploadBlobs(_ blobs: [REAPI.Digest: URL]) async throws {
        _ = try await call(Request(operation: .uploadBlobs, blobs: Self.encode(blobs)))
    }

    func downloadBlob(_ digest: REAPI.Digest, to path: URL) async throws {
        _ = try await call(Request(operation: .downloadBlob, blobs: Self.encode([digest: path])))
    }

    /// The caller owns the directory and backend lifetime, and must cancel and await this function before removing either.
    static func serve(directory: URL, remote: any REAPICacheStoring) async throws {
        try await serve(directory: directory, prepare: { remote })
    }

    static func serve(
        directory: URL, prepare: @Sendable () async throws -> (any REAPICacheStoring)?
    ) async throws {
        try CargoCacheIPC.validateDirectory(directory)
        let lock = try CargoCacheIPC.openLock(directory.appendingPathComponent("server.lock"))
        defer { try? lock.close() }
        guard flock(lock.fileDescriptor, LOCK_EX | LOCK_NB) == 0 else { throw BrokerError.busy }
        let marker = directory.appendingPathComponent("server.json")
        var server = Server(process: getpid(), identity: UUID(), ready: false)
        try CargoCacheIPC.write(server, to: marker)
        defer {
            CargoCacheIPC.remove(marker)
            for name in (try? CargoCacheIPC.filenames(directory)) ?? [] {
                if let id = CargoCacheIPC.requestID(name) {
                    CargoCacheIPC.remove(
                        directory.appendingPathComponent(name),
                        directory.appendingPathComponent(id + ".response")
                    )
                } else if CargoCacheIPC.requestID(name, suffix: ".active") != nil {
                    CargoCacheIPC.remove(directory.appendingPathComponent(name))
                }
            }
        }
        guard let remote = try await prepare() else { return }
        try Task.checkCancellation()
        server.ready = true
        try CargoCacheIPC.write(server, to: marker)
        let admissions = try CargoCacheIPC.openLock(directory.appendingPathComponent("requests.lock"))
        defer { try? admissions.close() }

        try await withThrowingTaskGroup(of: String?.self) { group in
            defer { group.cancelAll() }
            var active: [String: CargoCacheIPC.Lane] = [:]
            group.addTask { try await Task.sleep(for: .milliseconds(5)); return nil }
            while let completed = try await group.next() {
                try Task.checkCancellation()
                if let completed {
                    active[completed] = nil
                    CargoCacheIPC.remove(directory.appendingPathComponent(completed + ".active"))
                } else {
                    group.addTask { try await Task.sleep(for: .milliseconds(5)); return nil }
                }
                guard let names = try? CargoCacheIPC.filenames(directory) else { continue }
                for name in names where name.hasSuffix(".request") {
                    guard let id = CargoCacheIPC.requestID(name), active[id] == nil else { continue }
                    let request = directory.appendingPathComponent(name)
                    let response = directory.appendingPathComponent(id + ".response")
                    if FileManager.default.fileExists(atPath: response.path) {
                        if let message = try? CargoCacheIPC.read(Request.self, from: request), !alive(message.process) {
                            CargoCacheIPC.remove(request, response)
                        }
                        continue
                    }
                    let lane = (try? CargoCacheIPC.read(Request.self, from: request).operation.lane) ?? .publication
                    guard active.values.filter({ $0 == lane }).count < concurrency else { continue }
                    guard flock(admissions.fileDescriptor, LOCK_EX | LOCK_NB) == 0 else { continue }
                    defer { flock(admissions.fileDescriptor, LOCK_UN) }
                    guard let message = try? CargoCacheIPC.read(Request.self, from: request) else { continue }
                    do {
                        try CargoCacheIPC.write(message.operation, to: directory.appendingPathComponent(id + ".active"))
                    } catch {
                        CargoCacheIPC.remove(request, response)
                        continue
                    }
                    active[id] = lane
                    group.addTask {
                        await respond(id: id, directory: directory, remote: remote)
                        return id
                    }
                }
            }
        }
    }

    private typealias BrokerError = CargoCacheIPC.BrokerError
    private typealias Request = CargoCacheIPC.Request
    private typealias Response = CargoCacheIPC.Response
    private typealias Server = CargoCacheIPC.Server
    private typealias Blob = CargoCacheIPC.Blob
    private typealias Failure = CargoCacheIPC.Failure
    private static let concurrency = 8

    private func call(_ message: Request) async throws -> Response {
        _ = try message.validate()
        try CargoCacheIPC.validateDirectory(directory)
        let timing = Self.timing
        let startupDeadline = timing.now() + .seconds(1)
        let marker = directory.appendingPathComponent("server.json")
        var server: Server?
        while server == nil {
            try Task.checkCancellation()
            if let candidate = try? CargoCacheIPC.read(Server.self, from: marker) {
                guard Self.alive(candidate.process) else { throw BrokerError.unavailable }
                if candidate.ready != false { server = candidate }
            } else if timing.now() >= startupDeadline {
                throw BrokerError.unavailable
            }
            if server == nil { try await timing.sleep(.milliseconds(5)) }
        }
        guard let server, Self.alive(server.process) else { throw BrokerError.unavailable }
        let id = UUID().uuidString
        let request = directory.appendingPathComponent(id + ".request")
        let response = directory.appendingPathComponent(id + ".response")
        defer { CargoCacheIPC.remove(request, response) }
        try await publish(message, to: request, server: server)
        let acceptanceDeadline = timing.now() + .seconds(1)
        var deadline: ContinuousClock.Instant?
        while true {
            try Task.checkCancellation()
            if FileManager.default.fileExists(atPath: response.path) {
                let reply = try CargoCacheIPC.read(Response.self, from: response)
                guard (reply.result?.count ?? 0) <= CargoCacheIPC.maximumResultBytes,
                      reply.available.count <= CargoCacheIPC.maximumBlobs,
                      (reply.uploaded?.count ?? 0) <= CargoCacheIPC.maximumBlobs,
                      (reply.remoteFailures?.count ?? 0) <= CargoCacheIPC.maximumBlobs,
                      reply.failures.count <= CargoCacheIPC.maximumBlobs else { throw BrokerError.invalidMessage }
                if let error = reply.error { throw BrokerError.remote(error) }
                return reply
            }
            if let deadline {
                guard timing.now() < deadline else { throw BrokerError.timedOut }
            } else if (try? CargoCacheIPC.read(
                CargoCacheIPC.Operation.self, from: directory.appendingPathComponent(id + ".active")
            )) == message.operation {
                // The backend owns its operation timeout; allow local response delivery separately.
                deadline = timing.now() + message.allowance + .seconds(1)
            } else if timing.now() >= acceptanceDeadline {
                throw BrokerError.busy
            }
            guard Self.alive(server.process), (try? CargoCacheIPC.read(Server.self, from: marker)) == server
            else { throw BrokerError.unavailable }
            guard FileManager.default.fileExists(atPath: request.path) else { throw BrokerError.busy }
            try await timing.sleep(.milliseconds(5))
        }
    }

    private func publish(_ message: Request, to request: URL, server: Server) async throws {
        let lock = try CargoCacheIPC.openLock(directory.appendingPathComponent("requests.lock"))
        defer { try? lock.close() }
        let marker = directory.appendingPathComponent("server.json")
        var waitMilliseconds = 5
        while true {
            try Task.checkCancellation()
            guard Self.alive(server.process), (try? CargoCacheIPC.read(Server.self, from: marker)) == server
            else { throw BrokerError.unavailable }
            if flock(lock.fileDescriptor, LOCK_EX | LOCK_NB) == 0 {
                defer { flock(lock.fileDescriptor, LOCK_UN) }
                var pending: [String: CargoCacheIPC.Lane] = [:]
                for name in try CargoCacheIPC.filenames(directory) {
                    let path = directory.appendingPathComponent(name)
                    if let id = CargoCacheIPC.requestID(name),
                       let operation = try? CargoCacheIPC.read(Request.self, from: path).operation
                    {
                        pending[id] = operation.lane
                    } else if let id = CargoCacheIPC.requestID(name, suffix: ".active"),
                              let operation = try? CargoCacheIPC.read(CargoCacheIPC.Operation.self, from: path)
                    {
                        pending[id] = operation.lane
                    }
                }
                let lane = message.operation.lane
                let admitted = pending.values.filter { $0 == lane }.count
                if pending.count < CargoCacheIPC.maximumRequests, admitted < Self.concurrency {
                    try Task.checkCancellation()
                    try CargoCacheIPC.write(message, to: request)
                    return
                }
            }
            try await Task.sleep(for: .milliseconds(waitMilliseconds))
            waitMilliseconds = min(waitMilliseconds * 2, 50)
        }
    }

    private static func respond(id: String, directory: URL, remote: any REAPICacheStoring) async {
        let request = directory.appendingPathComponent(id + ".request")
        let response = directory.appendingPathComponent(id + ".response")
        do {
            let message = try CargoCacheIPC.read(Request.self, from: request)
            let files = try message.validate()
            guard alive(message.process) else { CargoCacheIPC.remove(request, response); return }
            let deadline = ContinuousClock.now + message.allowance
            let reply = try await withThrowingTaskGroup(of: Response.self) { group in
                defer { group.cancelAll() }
                group.addTask { try await execute(message, files: files, remote: remote) }
                group.addTask {
                    while true {
                        try Task.checkCancellation()
                        guard alive(message.process), FileManager.default.fileExists(atPath: request.path) else {
                            throw CancellationError()
                        }
                        guard ContinuousClock.now < deadline else { throw BrokerError.timedOut }
                        try await Task.sleep(for: .milliseconds(20))
                    }
                }
                guard let reply = try await group.next() else { throw CancellationError() }
                return reply
            }
            try Task.checkCancellation()
            if alive(message.process), FileManager.default.fileExists(atPath: request.path) {
                try CargoCacheIPC.write(reply, to: response)
                if !FileManager.default.fileExists(atPath: request.path) { CargoCacheIPC.remove(response) }
            } else {
                CargoCacheIPC.remove(request, response)
            }
        } catch {
            if error is CancellationError || Task.isCancelled {
                CargoCacheIPC.remove(request, response)
            } else if FileManager.default.fileExists(atPath: request.path) {
                do {
                    try CargoCacheIPC.write(Response(error: String(REAPI.describe(error).prefix(2048))), to: response)
                } catch {
                    CargoCacheIPC.remove(request, response)
                }
                if !FileManager.default.fileExists(atPath: request.path) { CargoCacheIPC.remove(response) }
            }
        }
    }

    private static func execute(
        _ request: Request, files: [REAPI.Digest: URL], remote: any REAPICacheStoring
    ) async throws -> Response {
        try Task.checkCancellation()
        switch request.operation {
        case .actionResult:
            let result = try await remote.actionResult(for: CargoCacheIPC.digest(request.digest ?? Data()))
            let data = try result?.serializedData()
            guard (data?.count ?? 0) <= CargoCacheIPC.maximumResultBytes else { throw BrokerError.invalidMessage }
            return Response(result: data)
        case .containsActionResult:
            let contains = try await remote.containsActionResult(for: CargoCacheIPC.digest(request.digest ?? Data()))
            return Response(contains: contains)
        case .storeActionResult:
            try await remote.storeActionResult(
                REAPI.ActionResult(serializedBytes: request.result ?? Data()), for: CargoCacheIPC.digest(request.digest ?? Data())
            )
        case .uploadAvailableBlobs:
            let upload = try await remote.uploadAvailableBlobs(files)
            guard upload.available.isSubset(of: Set(files.keys)),
                  (upload.uploaded ?? []).isSubset(of: upload.available),
                  Set(upload.failures.keys).isSubset(of: Set(files.keys)), upload.failures.count <= CargoCacheIPC.maximumBlobs
            else {
                throw BrokerError.invalidMessage
            }
            return try Response(
                available: upload.available.map { try $0.serializedData() },
                uploaded: upload.uploaded.map { try $0.map { try $0.serializedData() } },
                failures: upload.failures.map { try Failure(digest: $0.key.serializedData(), reason: $0.value) }
            )
        case .downloadAvailableBlobs:
            let download = try await remote.downloadBlobs(files)
            guard download.available.isSubset(of: Set(files.keys)),
                  download.remoteFailures.isSubset(of: Set(files.keys)),
                  download.available.isDisjoint(with: download.remoteFailures) else { throw BrokerError.invalidMessage }
            return try Response(
                available: download.available.map { try $0.serializedData() },
                remoteFailures: download.remoteFailures.map { try $0.serializedData() }
            )
        case .uploadBlobs:
            try await remote.uploadBlobs(files)
        case .downloadBlob:
            guard let (digest, path) = files.first else { throw BrokerError.invalidMessage }
            try await remote.downloadBlob(digest, to: path)
        }
        return Response()
    }

    private static func encode(_ files: [REAPI.Digest: URL]) throws -> [Blob] {
        guard files.count <= CargoCacheIPC.maximumBlobs,
              files.values.allSatisfy(\.isFileURL) else { throw BrokerError.invalidMessage }
        return try files.map { try Blob(digest: $0.key.serializedData(), path: $0.value.path) }
    }

    private static func digests(_ data: [Data], within files: [REAPI.Digest: URL]) throws -> Set<REAPI.Digest> {
        let values = try Set(data.map(CargoCacheIPC.digest))
        guard values.count == data.count, values.isSubset(of: Set(files.keys)) else { throw BrokerError.invalidMessage }
        return values
    }

    private static func alive(_ process: Int32) -> Bool {
        process > 0 && (kill(process, 0) == 0 || errno == EPERM)
    }
}

private enum CargoCacheIPC {
    static let maximumRequests = 64
    static let maximumResultBytes = 2_000_000
    static let maximumBlobs = 256
    private static let maximumBlobBytes: Int64 = 100_000_000
    private static let maximumTransferBytes: Int64 = 256_000_000
    private static let maximumMessageBytes = 4_000_000

    enum Lane { case metadata, download, publication }

    enum Operation: String, Codable, Sendable {
        case actionResult, containsActionResult, storeActionResult
        case uploadAvailableBlobs, downloadAvailableBlobs, uploadBlobs, downloadBlob

        var lane: Lane {
            switch self {
            case .actionResult, .containsActionResult: .metadata
            case .downloadAvailableBlobs, .downloadBlob: .download
            case .storeActionResult, .uploadAvailableBlobs, .uploadBlobs: .publication
            }
        }
    }

    struct Server: Codable, Equatable {
        let process: Int32
        let identity: UUID
        var ready: Bool?
    }

    struct Blob: Codable, Sendable {
        let digest: Data
        let path: String
    }

    struct Request: Codable, Sendable {
        let operation: Operation
        var process: Int32 = getpid()
        var digest: Data?
        var result: Data?
        var blobs: [Blob] = []

        func validate() throws -> [REAPI.Digest: URL] {
            guard process > 0, blobs.count <= CargoCacheIPC.maximumBlobs,
                  (result?.count ?? 0) <= CargoCacheIPC.maximumResultBytes else { throw BrokerError.invalidMessage }
            if let digest { _ = try CargoCacheIPC.digest(digest) }
            var bytes: Int64 = 0
            var files: [REAPI.Digest: URL] = [:]
            for blob in blobs {
                let digest = try CargoCacheIPC.digest(blob.digest)
                guard digest.sizeBytes <= CargoCacheIPC.maximumBlobBytes,
                      digest.sizeBytes <= CargoCacheIPC.maximumTransferBytes - bytes,
                      blob.path.hasPrefix("/"), blob.path.utf8.count <= 4096, !blob.path.utf8.contains(0),
                      files[digest] == nil else { throw BrokerError.invalidMessage }
                bytes += digest.sizeBytes
                files[digest] = URL(fileURLWithPath: blob.path)
            }
            switch operation {
            case .actionResult, .containsActionResult:
                guard digest != nil, result == nil, blobs.isEmpty else { throw BrokerError.invalidMessage }
            case .storeActionResult:
                guard digest != nil, result != nil, blobs.isEmpty else { throw BrokerError.invalidMessage }
            case .downloadBlob:
                guard files.count == 1, digest == nil, result == nil else { throw BrokerError.invalidMessage }
            case .uploadBlobs, .uploadAvailableBlobs, .downloadAvailableBlobs:
                guard digest == nil, result == nil else { throw BrokerError.invalidMessage }
            }
            return files
        }

        var allowance: Duration {
            switch operation {
            case .actionResult, .containsActionResult:
                return REAPICacheClient.metadataReadAllowance(timeout: CargoRemoteCache.metadataTimeout)
            case .storeActionResult: return .seconds(120)
            default:
                // Cover the backend's three upload attempts and admission backoff, at its default slow-link floor.
                let bytes = blobs.reduce(Int64(0)) { $0 + ((try? CargoCacheIPC.digest($1.digest).sizeBytes) ?? 0) }
                let guards = REAPICacheClient.TransferGuards.default
                return (guards.baseAllowance + .seconds(bytes / guards.slowestBytesPerSecond)) * 3 + .seconds(60)
            }
        }
    }

    struct Failure: Codable, Sendable {
        let digest: Data
        let reason: String
    }

    struct Response: Codable, Sendable {
        var result: Data?
        var contains: Bool?
        var available: [Data] = []
        var uploaded: [Data]?
        var remoteFailures: [Data]?
        var failures: [Failure] = []
        var error: String?
    }

    enum BrokerError: Error, LocalizedError {
        case invalidDirectory, invalidMessage, busy, unavailable, timedOut
        case remote(String)

        var errorDescription: String? {
            switch self {
            case .invalidDirectory: "The Cargo cache broker directory is not private."
            case .invalidMessage: "The Cargo cache broker message is invalid or exceeds its bounds."
            case .busy: "The Cargo cache broker could not admit this request."
            case .unavailable: "The Cargo cache broker is not running."
            case .timedOut: "The Cargo cache broker request timed out."
            case let .remote(reason): reason
            }
        }
    }

    static func validateDirectory(_ directory: URL) throws {
        var info = stat()
        guard directory.isFileURL, lstat(directory.path, &info) == 0,
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR), info.st_uid == geteuid(),
              info.st_mode & 0o777 == 0o700 else { throw BrokerError.invalidDirectory }
    }

    static func digest(_ data: Data) throws -> REAPI.Digest {
        guard data.count <= 256 else { throw BrokerError.invalidMessage }
        let digest = try REAPI.Digest(serializedBytes: data)
        try REAPI.validate(digest)
        return digest
    }

    static func requestID(_ name: String, suffix: String = ".request") -> String? {
        guard name.hasSuffix(suffix) else { return nil }
        let id = String(name.dropLast(suffix.count))
        return UUID(uuidString: id)?.uuidString == id ? id : nil
    }

    static func filenames(_ directory: URL) throws -> [String] {
        guard let handle = opendir(directory.path) else { throw BrokerError.unavailable }
        defer { closedir(handle) }
        var names: [String] = []
        while let entry = readdir(handle) {
            let name = withUnsafePointer(to: entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: entry.pointee.d_name)) {
                    String(cString: $0)
                }
            }
            if name == "." || name == ".." { continue }
            guard names.count < maximumRequests * 4 + 8 else { throw BrokerError.busy }
            names.append(name)
        }
        guard names.filter({ requestID($0) != nil }).count <= maximumRequests else { throw BrokerError.busy }
        return names
    }

    static func openLock(_ path: URL) throws -> FileHandle {
        let descriptor = open(path.path, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK, mode_t(0o600))
        guard descriptor >= 0 else { throw BrokerError.unavailable }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            close(descriptor)
            throw BrokerError.invalidMessage
        }
        return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }

    static func read<T: Decodable>(_ type: T.Type, from path: URL) throws -> T {
        let descriptor = open(path.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { throw BrokerError.unavailable }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              info.st_size >= 0, info.st_size <= maximumMessageBytes else { throw BrokerError.invalidMessage }
        let data = try handle.read(upToCount: Int(info.st_size) + 1) ?? Data()
        guard data.count == Int(info.st_size) else { throw BrokerError.invalidMessage }
        return try JSONDecoder().decode(type, from: data)
    }

    static func write(_ value: some Encodable, to path: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = try encoder.encode(value)
        guard data.count <= maximumMessageBytes else { throw BrokerError.invalidMessage }
        let temporary = path.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".tmp")
        defer { remove(temporary) }
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, mode_t(0o600))
        guard descriptor >= 0 else { throw BrokerError.unavailable }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        try handle.write(contentsOf: data)
        guard rename(temporary.path, path.path) == 0 else { throw BrokerError.unavailable }
    }

    static func remove(_ paths: URL...) {
        for path in paths {
            try? FileManager.default.removeItem(at: path)
        }
    }
}
