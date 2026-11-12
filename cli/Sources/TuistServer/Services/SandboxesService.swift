import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
import Mockable
import OpenAPIRuntime
import TuistHTTP

public typealias SandboxesPage = Operations.listSandboxes.Output.Ok.Body.jsonPayload
public typealias ServerSandbox = Components.Schemas.Sandbox
public typealias ServerSandboxPlatform = Operations.createSandbox.Input.Body.jsonPayload.platformPayload
public typealias SandboxAnalytics = Operations.getSandboxAnalytics.Output.Ok.Body.jsonPayload
public typealias ServerSandboxCommand = Components.Schemas.SandboxCommand
public typealias ServerSandboxCommandLogLine = Components.Schemas.SandboxCommandLogLine

/// A sandbox action that answers the sandbox it changed.
public enum SandboxTransition: String, Sendable {
    case pause, resume, archive
}

/// The sandbox API (`/api/accounts/:account_handle/sandboxes`).
@Mockable
public protocol SandboxesServicing: Sendable {
    func listSandboxes(
        accountHandle: String,
        serverURL: URL,
        search: String?,
        status: String?,
        vcpus: Int?,
        sortBy: String?,
        sortOrder: String?,
        page: Int,
        pageSize: Int
    ) async throws -> SandboxesPage
    func getSandbox(accountHandle: String, serverURL: URL, sandboxID: String) async throws -> ServerSandbox
    func getSandboxAnalytics(accountHandle: String, serverURL: URL, start: Date?, end: Date?) async throws
        -> SandboxAnalytics
    func createSandbox(
        accountHandle: String,
        serverURL: URL,
        platform: ServerSandboxPlatform?,
        template: String?,
        vcpus: Int?,
        memoryMB: Int?,
        workspaceGB: Int?
    ) async throws -> ServerSandbox
    func transitionSandbox(
        _ transition: SandboxTransition,
        accountHandle: String,
        serverURL: URL,
        sandboxID: String
    ) async throws -> ServerSandbox
    func deleteSandbox(accountHandle: String, serverURL: URL, sandboxID: String) async throws
    /// Starts a command detached in the sandbox (`POST .../commands`), which outlives any one request.
    func startSandboxCommand(
        accountHandle: String,
        serverURL: URL,
        sandboxID: String,
        command: String,
        cwd: String?,
        environment: [String: String],
        stdin: Bool,
        timeoutMs: Int?
    ) async throws -> ServerSandboxCommand
    /// The command's output from the given byte offsets, line by line as the server streams it. The last line is
    /// `exit` or `error`, unless the server ended a long stream early, which a caller resumes from the last offsets.
    func streamSandboxCommandLogs(
        accountHandle: String,
        serverURL: URL,
        sandboxID: String,
        commandID: String,
        stdoutOffset: Int,
        stderrOffset: Int
    ) async throws -> AsyncThrowingStream<ServerSandboxCommandLogLine, any Error>
    func writeSandboxCommandStdin(
        accountHandle: String,
        serverURL: URL,
        sandboxID: String,
        commandID: String,
        data: Data,
        close: Bool
    ) async throws
    func cancelSandboxCommand(
        accountHandle: String,
        serverURL: URL,
        sandboxID: String,
        commandID: String
    ) async throws -> ServerSandboxCommand
    /// Puts the file at `file` in the account's storage and returns a URL a command in the sandbox downloads it from
    /// within the hour, which is much faster for a large file than a command's stdin.
    func uploadSandboxFile(accountHandle: String, serverURL: URL, sandboxID: String, file: URL) async throws -> URL
}

public enum SandboxesServiceError: LocalizedError, Equatable {
    /// The server's own message for a refused request.
    case refused(String)
    /// The server has no node for the sandbox right now (503), such as while CI holds a shared macOS host.
    case unavailable(String)
    /// The sandbox or command no longer exists (404).
    case notFound(String)
    case limited
    case invalidShape
    case unknownError(Int)

    public var errorDescription: String? {
        switch self {
        case let .refused(message), let .unavailable(message), let .notFound(message):
            return message
        case .limited:
            return "Tuist refused the request for now: the account may have reached its sandbox CPU or memory limit, or sent too many requests. Retry later."
        case .invalidShape:
            return "Use 2, 4 or 8 vCPUs with 4096, 8192 or 16384 MB of memory."
        case let .unknownError(statusCode):
            return "The sandbox request failed with an unexpected Tuist response of \(statusCode)."
        }
    }

    /// Sandbox errors carry `{"message": …}` whatever their status, so one the spec does not list, such as a 500,
    /// still shows the server's reason. A body without one falls back to the status code.
    static func undocumented(_ statusCode: Int, _ payload: UndocumentedPayload) async -> SandboxesServiceError {
        struct Body: Decodable { let message: String }
        guard let body = payload.body,
              let data = try? await Data(collecting: body, upTo: 1_048_576),
              let message = try? JSONDecoder().decode(Body.self, from: data).message
        else { return .unknownError(statusCode) }
        return statusCode == 503 ? .unavailable(message) : .refused(message)
    }

    /// The generated client decodes a documented error status as `{"message": …}` before answering, so an error page
    /// from a proxy in front of Tuist, such as Cloudflare's `error code: 502`, fails as a decoding error. Report its
    /// status instead.
    static func send<Output>(_ operation: () async throws -> Output) async throws -> Output {
        do {
            return try await operation()
        } catch let error as ClientError {
            guard let statusCode = error.response?.status.code, statusCode >= 400 else { throw error }
            throw unknownError(statusCode)
        }
    }
}

public struct SandboxesService: SandboxesServicing {
    public init() {}

    public func listSandboxes(
        accountHandle: String,
        serverURL: URL,
        search: String?,
        status: String?,
        vcpus: Int?,
        sortBy: String?,
        sortOrder: String?,
        page: Int,
        pageSize: Int
    ) async throws -> SandboxesPage {
        let response = try await SandboxesServiceError.send {
            try await Client.authenticated(serverURL: serverURL).listSandboxes(.init(
                path: .init(account_handle: accountHandle),
                query: .init(
                    page: page,
                    page_size: pageSize,
                    search: search,
                    sort_by: sortBy.flatMap { .init(rawValue: $0) },
                    sort_order: sortOrder.flatMap { .init(rawValue: $0) },
                    status: status.flatMap { .init(rawValue: $0) },
                    vcpus: vcpus
                )
            ))
        }
        switch response {
        case let .ok(value): return try value.body.json
        case let .badRequest(value): throw SandboxesServiceError.refused(try value.body.json.message)
        case let .forbidden(value): throw SandboxesServiceError.refused(try value.body.json.message)
        case .tooManyRequests: throw SandboxesServiceError.limited
        case let .undocumented(statusCode, payload): throw await SandboxesServiceError.undocumented(statusCode, payload)
        }
    }

    public func getSandbox(accountHandle: String, serverURL: URL, sandboxID: String) async throws -> ServerSandbox {
        let response = try await SandboxesServiceError.send {
            try await Client.authenticated(serverURL: serverURL).getSandbox(.init(
                path: .init(account_handle: accountHandle, sandbox_id: sandboxID)
            ))
        }
        switch response {
        case let .ok(value): return try Self.convert(value.body.json)
        case let .forbidden(value): throw SandboxesServiceError.refused(try value.body.json.message)
        case let .notFound(value): throw SandboxesServiceError.refused(try value.body.json.message)
        case .tooManyRequests: throw SandboxesServiceError.limited
        case let .undocumented(statusCode, payload): throw await SandboxesServiceError.undocumented(statusCode, payload)
        }
    }

    public func getSandboxAnalytics(
        accountHandle: String,
        serverURL: URL,
        start: Date?,
        end: Date?
    ) async throws -> SandboxAnalytics {
        let response = try await SandboxesServiceError.send {
            try await Client.authenticated(serverURL: serverURL).getSandboxAnalytics(.init(
                path: .init(account_handle: accountHandle),
                query: .init(end: end, start: start)
            ))
        }
        switch response {
        case let .ok(value): return try value.body.json
        case let .badRequest(value): throw SandboxesServiceError.refused(try value.body.json.message)
        case let .forbidden(value): throw SandboxesServiceError.refused(try value.body.json.message)
        case .tooManyRequests: throw SandboxesServiceError.limited
        case let .undocumented(statusCode, payload): throw await SandboxesServiceError.undocumented(statusCode, payload)
        }
    }

    public func createSandbox(
        accountHandle: String,
        serverURL: URL,
        platform: ServerSandboxPlatform?,
        template: String?,
        vcpus: Int?,
        memoryMB: Int?,
        workspaceGB: Int?
    ) async throws -> ServerSandbox {
        typealias Body = Operations.createSandbox.Input.Body.jsonPayload
        let shapeVCPUs = try vcpus.map { try Body.vcpusPayload(rawValue: $0) ?? { throw SandboxesServiceError.invalidShape }() }
        let shapeMemory = try memoryMB.map {
            try Body.memory_mbPayload(rawValue: $0) ?? { throw SandboxesServiceError.invalidShape }()
        }
        let response = try await SandboxesServiceError.send {
            try await Client.authenticated(serverURL: serverURL).createSandbox(.init(
                path: .init(account_handle: accountHandle),
                body: .json(.init(
                    memory_mb: shapeMemory,
                    platform: platform,
                    template: template,
                    vcpus: shapeVCPUs,
                    workspace_gb: workspaceGB
                ))
            ))
        }
        switch response {
        case let .created(value): return try Self.convert(value.body.json)
        case let .badRequest(value): throw SandboxesServiceError.refused(try value.body.json.message)
        case let .forbidden(value): throw SandboxesServiceError.refused(try value.body.json.message)
        case let .conflict(value): throw SandboxesServiceError.refused(try value.body.json.message)
        case let .badGateway(value): throw SandboxesServiceError.refused(try value.body.json.message)
        case let .serviceUnavailable(value): throw SandboxesServiceError.refused(try value.body.json.message)
        case let .gatewayTimeout(value): throw SandboxesServiceError.refused(try value.body.json.message)
        case .tooManyRequests: throw SandboxesServiceError.limited
        case let .undocumented(statusCode, payload): throw await SandboxesServiceError.undocumented(statusCode, payload)
        }
    }

    public func transitionSandbox(
        _ transition: SandboxTransition,
        accountHandle: String,
        serverURL: URL,
        sandboxID: String
    ) async throws -> ServerSandbox {
        let client = Client.authenticated(serverURL: serverURL)
        switch transition {
        case .pause:
            let response = try await SandboxesServiceError.send {
                try await client.pauseSandbox(.init(path: .init(account_handle: accountHandle, sandbox_id: sandboxID)))
            }
            switch response {
            case let .ok(value): return try Self.convert(value.body.json)
            case let .forbidden(value): throw SandboxesServiceError.refused(try value.body.json.message)
            case let .notFound(value): throw SandboxesServiceError.refused(try value.body.json.message)
            case let .conflict(value): throw SandboxesServiceError.refused(try value.body.json.message)
            case let .badGateway(value): throw SandboxesServiceError.refused(try value.body.json.message)
            case let .serviceUnavailable(value): throw SandboxesServiceError.refused(try value.body.json.message)
            case let .gatewayTimeout(value): throw SandboxesServiceError.refused(try value.body.json.message)
            case .tooManyRequests: throw SandboxesServiceError.limited
            case let .undocumented(statusCode, payload): throw await SandboxesServiceError.undocumented(statusCode, payload)
            }
        case .resume:
            let response = try await SandboxesServiceError.send {
                try await client.resumeSandbox(.init(path: .init(account_handle: accountHandle, sandbox_id: sandboxID)))
            }
            switch response {
            case let .ok(value): return try Self.convert(value.body.json)
            case let .forbidden(value): throw SandboxesServiceError.refused(try value.body.json.message)
            case let .notFound(value): throw SandboxesServiceError.refused(try value.body.json.message)
            case let .conflict(value): throw SandboxesServiceError.refused(try value.body.json.message)
            case let .badGateway(value): throw SandboxesServiceError.refused(try value.body.json.message)
            case let .serviceUnavailable(value): throw SandboxesServiceError.refused(try value.body.json.message)
            case let .gatewayTimeout(value): throw SandboxesServiceError.refused(try value.body.json.message)
            case .tooManyRequests: throw SandboxesServiceError.limited
            case let .undocumented(statusCode, payload): throw await SandboxesServiceError.undocumented(statusCode, payload)
            }
        case .archive:
            let response = try await SandboxesServiceError.send {
                try await client.archiveSandbox(.init(path: .init(account_handle: accountHandle, sandbox_id: sandboxID)))
            }
            switch response {
            case let .accepted(value): return try Self.convert(value.body.json)
            case let .forbidden(value): throw SandboxesServiceError.refused(try value.body.json.message)
            case let .notFound(value): throw SandboxesServiceError.refused(try value.body.json.message)
            case let .conflict(value): throw SandboxesServiceError.refused(try value.body.json.message)
            case let .badGateway(value): throw SandboxesServiceError.refused(try value.body.json.message)
            case let .serviceUnavailable(value): throw SandboxesServiceError.refused(try value.body.json.message)
            case let .gatewayTimeout(value): throw SandboxesServiceError.refused(try value.body.json.message)
            case .tooManyRequests: throw SandboxesServiceError.limited
            case let .undocumented(statusCode, payload): throw await SandboxesServiceError.undocumented(statusCode, payload)
            }
        }
    }

    public func deleteSandbox(accountHandle: String, serverURL: URL, sandboxID: String) async throws {
        let response = try await SandboxesServiceError.send {
            try await Client.authenticated(serverURL: serverURL).deleteSandbox(.init(
                path: .init(account_handle: accountHandle, sandbox_id: sandboxID)
            ))
        }
        switch response {
        case .noContent: return
        case let .forbidden(value): throw SandboxesServiceError.refused(try value.body.json.message)
        case let .notFound(value): throw SandboxesServiceError.refused(try value.body.json.message)
        case let .conflict(value): throw SandboxesServiceError.refused(try value.body.json.message)
        case let .badGateway(value): throw SandboxesServiceError.refused(try value.body.json.message)
        case let .serviceUnavailable(value): throw SandboxesServiceError.refused(try value.body.json.message)
        case let .gatewayTimeout(value): throw SandboxesServiceError.refused(try value.body.json.message)
        case .tooManyRequests: throw SandboxesServiceError.limited
        case let .undocumented(statusCode, payload): throw await SandboxesServiceError.undocumented(statusCode, payload)
        }
    }

    public func startSandboxCommand(
        accountHandle: String,
        serverURL: URL,
        sandboxID: String,
        command: String,
        cwd: String?,
        environment: [String: String],
        stdin: Bool,
        timeoutMs: Int?
    ) async throws -> ServerSandboxCommand {
        let response = try await SandboxesServiceError.send {
            try await Client.authenticated(serverURL: serverURL).startSandboxCommand(.init(
                path: .init(account_handle: accountHandle, sandbox_id: sandboxID),
                body: .json(.init(
                    command: command,
                    cwd: cwd,
                    env: environment.isEmpty ? nil : .init(additionalProperties: environment),
                    stdin: stdin,
                    timeout_ms: timeoutMs
                ))
            ))
        }
        switch response {
        case let .accepted(value): return try Self.convert(value.body.json)
        case let .badRequest(value): throw SandboxesServiceError.refused(try value.body.json.message)
        case let .forbidden(value): throw SandboxesServiceError.refused(try value.body.json.message)
        case let .notFound(value): throw SandboxesServiceError.refused(try value.body.json.message)
        case let .conflict(value): throw SandboxesServiceError.refused(try value.body.json.message)
        case let .badGateway(value): throw SandboxesServiceError.refused(try value.body.json.message)
        case let .serviceUnavailable(value): throw SandboxesServiceError.unavailable(try value.body.json.message)
        case let .gatewayTimeout(value): throw SandboxesServiceError.refused(try value.body.json.message)
        case .tooManyRequests: throw SandboxesServiceError.limited
        case let .undocumented(statusCode, payload): throw await SandboxesServiceError.undocumented(statusCode, payload)
        }
    }

    public func streamSandboxCommandLogs(
        accountHandle: String,
        serverURL: URL,
        sandboxID: String,
        commandID: String,
        stdoutOffset: Int,
        stderrOffset: Int
    ) async throws -> AsyncThrowingStream<ServerSandboxCommandLogLine, any Error> {
        let response = try await SandboxesServiceError.send {
            try await Client.authenticated(serverURL: serverURL, streaming: true).streamSandboxCommandLogs(.init(
                path: .init(account_handle: accountHandle, sandbox_id: sandboxID, command_id: commandID),
                query: .init(stdout_offset: stdoutOffset, stderr_offset: stderrOffset)
            ))
        }
        let body: HTTPBody
        switch response {
        case let .ok(value): body = try value.body.application_x_hyphen_ndjson
        case let .forbidden(value): throw SandboxesServiceError.refused(try value.body.json.message)
        case let .notFound(value): throw SandboxesServiceError.notFound(try value.body.json.message)
        case let .conflict(value): throw SandboxesServiceError.refused(try value.body.json.message)
        case let .badGateway(value): throw SandboxesServiceError.refused(try value.body.json.message)
        case let .serviceUnavailable(value): throw SandboxesServiceError.unavailable(try value.body.json.message)
        case let .gatewayTimeout(value): throw SandboxesServiceError.refused(try value.body.json.message)
        case .tooManyRequests: throw SandboxesServiceError.limited
        case let .undocumented(statusCode, payload): throw await SandboxesServiceError.undocumented(statusCode, payload)
        }
        return AsyncThrowingStream { continuation in
            let reader = Task {
                do {
                    let decoder = JSONDecoder()
                    var buffer: [UInt8] = []
                    for try await chunk in body {
                        buffer.append(contentsOf: chunk)
                        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                            let line = buffer[..<newline]
                            if !line.allSatisfy({ $0 == UInt8(ascii: " ") || $0 == UInt8(ascii: "\r") }) {
                                continuation.yield(try decoder.decode(ServerSandboxCommandLogLine.self, from: Data(line)))
                            }
                            buffer.removeSubrange(...newline)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in reader.cancel() }
        }
    }

    public func writeSandboxCommandStdin(
        accountHandle: String,
        serverURL: URL,
        sandboxID: String,
        commandID: String,
        data: Data,
        close: Bool
    ) async throws {
        let response = try await SandboxesServiceError.send {
            try await Client.authenticated(serverURL: serverURL).writeSandboxCommandStdin(.init(
                path: .init(account_handle: accountHandle, sandbox_id: sandboxID, command_id: commandID),
                body: .json(.init(close: close, data: Base64EncodedData(data)))
            ))
        }
        switch response {
        case .ok: return
        case let .badRequest(value): throw SandboxesServiceError.refused(try value.body.json.message)
        case let .forbidden(value): throw SandboxesServiceError.refused(try value.body.json.message)
        case let .notFound(value): throw SandboxesServiceError.notFound(try value.body.json.message)
        case let .conflict(value): throw SandboxesServiceError.refused(try value.body.json.message)
        case let .badGateway(value): throw SandboxesServiceError.refused(try value.body.json.message)
        case let .serviceUnavailable(value): throw SandboxesServiceError.unavailable(try value.body.json.message)
        case let .gatewayTimeout(value): throw SandboxesServiceError.refused(try value.body.json.message)
        case .tooManyRequests: throw SandboxesServiceError.limited
        case let .undocumented(statusCode, payload): throw await SandboxesServiceError.undocumented(statusCode, payload)
        }
    }

    public func cancelSandboxCommand(
        accountHandle: String,
        serverURL: URL,
        sandboxID: String,
        commandID: String
    ) async throws -> ServerSandboxCommand {
        let response = try await SandboxesServiceError.send {
            try await Client.authenticated(serverURL: serverURL).cancelSandboxCommand(.init(
                path: .init(account_handle: accountHandle, sandbox_id: sandboxID, command_id: commandID)
            ))
        }
        switch response {
        case let .ok(value): return try Self.convert(value.body.json)
        case let .forbidden(value): throw SandboxesServiceError.refused(try value.body.json.message)
        case let .notFound(value): throw SandboxesServiceError.notFound(try value.body.json.message)
        case let .conflict(value): throw SandboxesServiceError.refused(try value.body.json.message)
        case let .badGateway(value): throw SandboxesServiceError.refused(try value.body.json.message)
        case let .serviceUnavailable(value): throw SandboxesServiceError.unavailable(try value.body.json.message)
        case let .gatewayTimeout(value): throw SandboxesServiceError.refused(try value.body.json.message)
        case .tooManyRequests: throw SandboxesServiceError.limited
        case let .undocumented(statusCode, payload): throw await SandboxesServiceError.undocumented(statusCode, payload)
        }
    }

    public func uploadSandboxFile(accountHandle: String, serverURL: URL, sandboxID: String, file: URL) async throws -> URL {
        let response = try await SandboxesServiceError.send {
            try await Client.authenticated(serverURL: serverURL).createSandboxUpload(.init(
                path: .init(account_handle: accountHandle, sandbox_id: sandboxID)
            ))
        }
        switch response {
        case let .ok(value):
            let upload = try value.body.json
            guard let uploadURL = URL(string: upload.upload_url), let downloadURL = URL(string: upload.download_url) else {
                throw SandboxesServiceError.refused("Tuist answered an upload URL that is not valid.")
            }
            var request = URLRequest(url: uploadURL)
            request.httpMethod = "PUT"
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            request.addAzureBlobTypeHeaderIfNeeded()
            let (_, put) = try await RetryingURLTransfer(urlSession: .tuistLargeTransfer).upload(request, fromFile: file)
            let statusCode = (put as? HTTPURLResponse)?.statusCode ?? -1
            guard (200 ..< 300).contains(statusCode) else {
                throw SandboxesServiceError.refused("Uploading to the account's storage failed with status \(statusCode).")
            }
            return downloadURL
        case let .forbidden(value): throw SandboxesServiceError.refused(try value.body.json.message)
        case let .notFound(value): throw SandboxesServiceError.notFound(try value.body.json.message)
        case .tooManyRequests: throw SandboxesServiceError.limited
        case let .undocumented(statusCode, payload): throw await SandboxesServiceError.undocumented(statusCode, payload)
        }
    }

    /// Each operation's generated response type has the shape of the shared component schema; decoding it into
    /// that type lets callers handle every sandbox response alike.
    private static func convert<Value: Decodable>(_ payload: some Encodable) throws -> Value {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Value.self, from: encoder.encode(payload))
    }
}
