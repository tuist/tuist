import Foundation
import TuistServer

/// Runs commands in one sandbox through the commands API (`POST .../commands`), which starts them detached in the
/// guest and streams their output, so a command outlives any one request and the ~100-second proxy limit in front of
/// Tuist.
///
/// Sandboxes on macOS share hosts with CI, which comes first: while CI holds the host the server answers new work with
/// 503. Starting a command waits for the host, and a log stream that fails reconnects from its last offsets, for up to
/// `hostWait` without progress each.
///
/// A proxy in front of Tuist can answer 502 after the server acted, so starting a command and writing its stdin are
/// sent again after a gateway or transport error too: the command carries an id chosen here and each stdin write the
/// offset it continues, so the server starts the command and appends the bytes once.
struct SandboxRemote {
    struct Exit: Equatable {
        let status: String
        let exitCode: Int?
    }

    struct Captured {
        let exit: Exit
        let stdout: String
        let stderr: String
    }

    /// The most the server accepts in one stdin write, before base64.
    static let stdinChunkBytes = 256 * 1024

    let accountHandle: String
    let serverURL: URL
    let sandboxID: String
    let sandboxesService: SandboxesServicing
    var hostWait: TimeInterval = 15 * 60
    var sleep: @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }
    /// Told once per wait, such as "waiting for a host".
    var onWait: @Sendable (String) -> Void = { _ in }

    func start(
        _ command: String,
        cwd: String? = nil,
        environment: [String: String] = [:],
        stdin: Bool = false,
        timeoutMs: Int? = nil
    ) async throws -> ServerSandboxCommand {
        let id = UUID().uuidString.lowercased()
        return try await retrying {
            try await sandboxesService.startSandboxCommand(
                accountHandle: accountHandle,
                serverURL: serverURL,
                sandboxID: sandboxID,
                id: id,
                command: command,
                cwd: cwd,
                environment: environment,
                stdin: stdin,
                timeoutMs: timeoutMs
            )
        }
    }

    func cancel(_ commandID: String) async throws {
        _ = try await sandboxesService.cancelSandboxCommand(
            accountHandle: accountHandle,
            serverURL: serverURL,
            sandboxID: sandboxID,
            commandID: commandID
        )
    }

    /// Hands the command's output to `output` as it arrives, until the command ends.
    func follow(
        _ commandID: String,
        output: (_ isStandardError: Bool, _ data: String) throws -> Void
    ) async throws -> Exit {
        var offsets = (stdout: 0, stderr: 0)
        var failingSince: Date?
        var failures = 0
        while true {
            try Task.checkCancellation()
            var failure: (any Error)?
            var lostMessage: String?
            do {
                let lines = try await sandboxesService.streamSandboxCommandLogs(
                    accountHandle: accountHandle,
                    serverURL: serverURL,
                    sandboxID: sandboxID,
                    commandID: commandID,
                    stdoutOffset: offsets.stdout,
                    stderrOffset: offsets.stderr
                )
                for try await line in lines {
                    switch line._type {
                    case .stdout, .stderr:
                        let isStandardError = line._type == .stderr
                        try output(isStandardError, line.data ?? "")
                        if let offset = line.offset {
                            if isStandardError { offsets.stderr = offset } else { offsets.stdout = offset }
                        }
                        failingSince = nil
                        failures = 0
                    case .exit:
                        return Exit(status: line.status ?? "exited", exitCode: line.exit_code)
                    case .error:
                        // A read failed mid-stream, such as while CI holds the host; the command keeps running.
                        lostMessage = line.message ?? "the stream failed"
                    }
                }
            } catch {
                guard Self.isTransient(error) else { throw error }
                failure = error
            }
            // The server ends a long stream without an exit line; resume it.
            if failure == nil, lostMessage == nil {
                failingSince = nil
                failures = 0
                continue
            }
            let now = Date()
            let since = failingSince ?? now
            failingSince = since
            if now.timeIntervalSince(since) >= hostWait {
                throw failure ?? SandboxCommandError.lostTrack(lostMessage ?? "")
            }
            if failures == 0 { onWait("Reconnecting to the command's output: \(lostMessage ?? failure!.localizedDescription)") }
            failures += 1
            try await sleep(min(30, pow(2, Double(failures))))
        }
    }

    /// Runs `script` to the end and returns its output, for short steps.
    func capture(
        _ script: String,
        cwd: String? = nil,
        environment: [String: String] = [:],
        timeoutMs: Int? = 10 * 60 * 1000
    ) async throws -> Captured {
        let command = try await start(script, cwd: cwd, environment: environment, timeoutMs: timeoutMs)
        var stdout = ""
        var stderr = ""
        let exit = try await follow(command.id) { isStandardError, data in
            if isStandardError { stderr += data } else { stdout += data }
        }
        return Captured(exit: exit, stdout: stdout, stderr: stderr)
    }

    /// Writes the file at `local` to `remote` through a command's stdin, replacing it only once it is complete.
    func upload(_ local: URL, to remote: String) async throws {
        let command = try await start(
            #"set -e; mkdir -p "$(dirname "$TUIST_UPLOAD")"; cat > "$TUIST_UPLOAD.part"; mv "$TUIST_UPLOAD.part" "$TUIST_UPLOAD""#,
            environment: ["TUIST_UPLOAD": remote],
            stdin: true,
            timeoutMs: 60 * 60 * 1000
        )
        try await writeStdin(command.id, at: 0, file: local)
        var stderr = ""
        let exit = try await follow(command.id) { isStandardError, data in if isStandardError { stderr += data } }
        guard exit.exitCode == 0 else {
            throw SandboxCommandError.stepFailed("Uploading to \(remote)", stderr)
        }
    }

    /// Puts the file at `local` in the account's storage and returns a URL a command in the sandbox downloads it from
    /// within the hour, or nil when the server has no uploads, such as one from before them.
    func stage(_ local: URL) async throws -> URL? {
        do {
            return try await sandboxesService.uploadSandboxFile(
                accountHandle: accountHandle,
                serverURL: serverURL,
                sandboxID: sandboxID,
                file: local
            )
        } catch SandboxesServiceError.notFound(_), SandboxesServiceError.unknownError(404) {
            return nil
        }
    }

    /// Writes `prefix` and then the file at `file`, if any, to the stdin of a command started with `stdin: true`, and
    /// ends it unless `close` is false. `offset` is how many bytes earlier writes sent to the command's stdin; returns
    /// how many it holds after this one. `prefix` must fit in one write.
    @discardableResult
    func writeStdin(
        _ commandID: String,
        at offset: Int,
        _ prefix: Data = Data(),
        file: URL? = nil,
        close: Bool = true
    ) async throws -> Int {
        let handle = try file.map { try FileHandle(forReadingFrom: $0) }
        defer { try? handle?.close() }
        func read(_ count: Int) throws -> Data { try handle?.read(upToCount: count) ?? Data() }
        var offset = offset
        var chunk = try prefix + read(Self.stdinChunkBytes - prefix.count)
        repeat {
            let next = chunk.count < Self.stdinChunkBytes ? Data() : try read(Self.stdinChunkBytes)
            let data = chunk
            let at = offset
            try await retrying {
                try await sandboxesService.writeSandboxCommandStdin(
                    accountHandle: accountHandle,
                    serverURL: serverURL,
                    sandboxID: sandboxID,
                    commandID: commandID,
                    data: data,
                    offset: at,
                    close: close && next.isEmpty
                )
            }
            offset += data.count
            chunk = next
        } while !chunk.isEmpty
        return offset
    }

    /// Sends a request that is safe to send again until it gets an answer: through 503s while the host is held, and
    /// through gateway and transport errors that may hide an answer, for up to `hostWait`.
    private func retrying<Value>(_ call: () async throws -> Value) async throws -> Value {
        let deadline = Date().addingTimeInterval(hostWait)
        var attempt = 0
        while true {
            do {
                return try await call()
            } catch {
                guard Self.isTransient(error),
                      (error as? SandboxesServiceError) != SandboxesServiceError.limited,
                      Date() < deadline
                else { throw error }
                if attempt == 0 {
                    if case let SandboxesServiceError.unavailable(message) = error {
                        onWait("Waiting for a sandbox host: \(message)")
                    } else {
                        onWait("Retrying: \(error.localizedDescription)")
                    }
                }
                attempt += 1
                // A current server already waited for the host inside the request, so retry soon.
                try await sleep(min(5, 2 * pow(2, Double(attempt - 1))))
            }
        }
    }

    /// A dropped connection, an undecodable chunk or a server-side 5xx. A refusal, such as a 404 for a command that is
    /// gone, is final.
    static func isTransient(_ error: any Error) -> Bool {
        switch error {
        case is CancellationError: return false
        case let error as SandboxesServiceError:
            switch error {
            case .unavailable, .limited: return true
            case let .unknownError(statusCode): return statusCode >= 500
            case .refused, .notFound, .invalidShape: return false
            }
        default: return true
        }
    }
}
