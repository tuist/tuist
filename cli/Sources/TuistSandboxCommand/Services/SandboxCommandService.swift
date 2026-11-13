import ArgumentParser
import Foundation
import Noora
import Path
import TuistConfigLoader
import TuistEnvironment
import TuistHTTP
import TuistProcess
import TuistServer

enum SandboxCommandError: LocalizedError, Equatable {
    case missingAccount
    case commandKilled
    case lostTrack(String)
    case commandEnded(String)
    case stepFailed(String, String)
    case notAGitRepository(String)

    var errorDescription: String? {
        switch self {
        case .missingAccount:
            return "Pass --account or configure a project full handle."
        case .commandKilled:
            return "The command was killed before it exited."
        case let .lostTrack(reason):
            return "Lost track of the command's output: \(reason) The command may still be running in the sandbox."
        case let .commandEnded(status):
            return "The command ended without an exit code (\(status))."
        case let .stepFailed(step, output):
            let output = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return output.isEmpty ? "\(step) failed." : "\(step) failed:\n\(output.suffix(4000))"
        case let .notAGitRepository(path):
            return "\(path) is not in a Git repository. Sync mirrors a Git worktree."
        }
    }
}

/// Runs `tuist sandbox` subcommands against the sandbox API, which shares its contract with the MCP sandbox tools
/// (`server/lib/tuist/sandboxes/query.ex`).
struct SandboxCommandService {
    private let configLoader: ConfigLoading
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let fullHandleService: FullHandleServicing
    private let sandboxesService: SandboxesServicing
    private let commandRunner: CommandRunning

    init(
        configLoader: ConfigLoading = ConfigLoader(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        fullHandleService: FullHandleServicing = FullHandleService(),
        sandboxesService: SandboxesServicing = SandboxesService(),
        commandRunner: CommandRunning = CommandRunner()
    ) {
        self.configLoader = configLoader
        self.serverEnvironmentService = serverEnvironmentService
        self.fullHandleService = fullHandleService
        self.sandboxesService = sandboxesService
        self.commandRunner = commandRunner
    }

    func list(
        options: SandboxOptions.Values,
        search: String?,
        status: String?,
        vcpus: Int?,
        sortBy: String?,
        sortOrder: String?,
        page: Int,
        pageSize: Int
    ) async throws {
        let (accountHandle, serverURL) = try await resolve(options)
        let load = { (page: Int) in
            try await sandboxesService.listSandboxes(
                accountHandle: accountHandle,
                serverURL: serverURL,
                search: search,
                status: status,
                vcpus: vcpus,
                sortBy: sortBy,
                sortOrder: sortOrder,
                page: page,
                pageSize: pageSize
            )
        }
        let response = try await load(page)
        if options.json {
            try Noora.current.json(response)
            return
        }
        guard !response.sandboxes.isEmpty else {
            Noora.current.passthrough("No sandboxes found on page \(page).\n")
            return
        }
        try await Noora.current.paginatedTable(
            headers: ["ID", "Status", "Platform", "vCPUs", "Memory", "Last active"],
            pageSize: pageSize,
            totalPages: response.pagination_metadata.total_pages,
            startPage: page - 1,
            loadPage: { pageIndex in
                let sandboxes = pageIndex == page - 1 ? response.sandboxes : try await load(pageIndex + 1).sandboxes
                return sandboxes.map(SandboxOutput.row)
            }
        )
    }

    func show(options: SandboxOptions.Values, sandboxID: String) async throws {
        let (accountHandle, serverURL) = try await resolve(options)
        let sandbox = try await sandboxesService.getSandbox(
            accountHandle: accountHandle,
            serverURL: serverURL,
            sandboxID: sandboxID
        )
        try output(sandbox, options: options) { SandboxOutput.details($0) }
    }

    func analytics(options: SandboxOptions.Values, start: Date?, end: Date?) async throws {
        let (accountHandle, serverURL) = try await resolve(options)
        let analytics = try await sandboxesService.getSandboxAnalytics(
            accountHandle: accountHandle,
            serverURL: serverURL,
            start: start,
            end: end
        )
        try output(analytics, options: options) { SandboxOutput.analytics($0) }
    }

    func create(
        options: SandboxOptions.Values,
        platform: ServerSandboxPlatform?,
        template: String?,
        vcpus: Int?,
        memoryGB: Int?,
        workspaceGB: Int?
    ) async throws {
        let (accountHandle, serverURL) = try await resolve(options)
        let sandbox = try await step("Booting sandbox...", done: "Sandbox booted", options: options) {
            try await sandboxesService.createSandbox(
                accountHandle: accountHandle,
                serverURL: serverURL,
                platform: platform,
                template: template,
                vcpus: vcpus,
                memoryMB: memoryGB.map { $0 * 1024 },
                workspaceGB: workspaceGB
            )
        }
        try output(sandbox, options: options) { SandboxOutput.details($0) }
    }

    /// Streams the command's output as it runs, however long that is, and exits with its status, so scripts can rely
    /// on it as on a local command. An interrupt cancels the command in the sandbox. With `--json`, the output is
    /// printed as one object once the command ends.
    func exec(
        options: SandboxOptions.Values,
        sandboxID: String,
        command: String,
        cwd: String?,
        environment: [String: String],
        timeoutMs: Int?
    ) async throws {
        let remote = try await remote(options, sandboxID: sandboxID)
        let started = try await remote.start(command, cwd: cwd, environment: environment, timeoutMs: timeoutMs)
        let signals = Self.onInterrupt { try? await remote.cancel(started.id) }
        defer { signals.forEach { $0.cancel() } }
        var stdout = ""
        var stderr = ""
        let exit = try await remote.follow(started.id) { isStandardError, data in
            if options.json {
                if isStandardError { stderr += data } else { stdout += data }
            } else {
                (isStandardError ? FileHandle.standardError : FileHandle.standardOutput).write(Data(data.utf8))
            }
        }
        if options.json {
            try Noora.current.json(SandboxExecOutput(
                status: exit.status,
                exitCode: exit.exitCode,
                stdout: stdout,
                stderr: stderr
            ))
        }
        switch (exit.status, exit.exitCode) {
        case (_, 0?): return
        case let (_, exitCode?): throw ExitCode(Int32(clamping: exitCode))
        case ("timed_out", nil):
            Self.note("The command timed out.")
            throw ExitCode(124)
        case ("cancelled", nil): throw ExitCode(130)
        case let (status, nil): throw SandboxCommandError.commandEnded(status)
        }
    }

    private struct SandboxExecOutput: Codable {
        let status: String
        let exitCode: Int?
        let stdout: String
        let stderr: String

        enum CodingKeys: String, CodingKey {
            case status, stdout, stderr
            case exitCode = "exit_code"
        }
    }

    /// Mirrors the Git worktree at `options.path` (default: the working directory) into the sandbox.
    func sync(options: SandboxOptions.Values, sandboxID: String, destination: String?) async throws {
        let directory = try await Environment.current.pathRelativeToWorkingDirectory(options.path)
        let topLevel = try? await commandRunner.run(
            arguments: ["git", "-C", directory.pathString, "rev-parse", "--show-toplevel"]
        ).concatenatedString(including: [.standardOutput]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let topLevel, let repository = try? AbsolutePath(validating: topLevel) else {
            throw SandboxCommandError.notAGitRepository(directory.pathString)
        }
        let remote = try await remote(options, sandboxID: sandboxID)
        let interactive = isatty(STDOUT_FILENO) == 1
        let result = try await step("Syncing the worktree...", done: "Worktree synced", options: options, show: interactive) {
            try await SandboxSync(remote: remote, commandRunner: commandRunner).sync(
                repository: repository,
                destination: destination
            )
        }
        try output(result, options: options) { result in
            guard result.uploaded else { return "\(result.root) is already up to date." }
            let size = ByteCountFormatter.string(fromByteCount: Int64(result.bytes), countStyle: .file)
            let files = result.changedFiles == 1 ? "1 changed file" : "\(result.changedFiles) changed files"
            return "Synced \(files) (\(size)) to \(result.root)."
        }
    }

    /// Copies a file or directory out of the sandbox to `localPath`, or into it when that is an existing directory or
    /// ends with `/`.
    func download(options: SandboxOptions.Values, sandboxID: String, remotePath: String, localPath: String) async throws {
        let requested = try await Environment.current.pathRelativeToWorkingDirectory(localPath)
        let copy = SandboxCopy(remote: try await remote(options, sandboxID: sandboxID), commandRunner: commandRunner)
        let path = try await copy.download(remotePath, to: requested, into: localPath.hasSuffix("/"))
        try copied(remotePath, to: path.pathString, options: options)
    }

    /// Copies a local file or directory into the sandbox at `remotePath`, or into it when that is an existing
    /// directory there or ends with `/`.
    func upload(options: SandboxOptions.Values, sandboxID: String, localPath: String, remotePath: String) async throws {
        let source = try await Environment.current.pathRelativeToWorkingDirectory(localPath)
        guard FileManager.default.fileExists(atPath: source.pathString) else {
            throw SandboxCommandError.stepFailed("Copying \(localPath) to the sandbox", "\(source.pathString) does not exist.")
        }
        let copy = SandboxCopy(remote: try await remote(options, sandboxID: sandboxID), commandRunner: commandRunner)
        let path = try await copy.upload(source, to: remotePath)
        try copied(source.pathString, to: path, options: options)
    }

    private func copied(_ source: String, to path: String, options: SandboxOptions.Values) throws {
        if options.json {
            try Noora.current.json(SandboxCopied(path: path))
        } else {
            Noora.current.passthrough("Copied \(source) to \(path).\n")
        }
    }

    private struct SandboxCopied: Codable {
        let path: String
    }

    private func remote(_ options: SandboxOptions.Values, sandboxID: String) async throws -> SandboxRemote {
        let (accountHandle, serverURL) = try await resolve(options)
        var remote = SandboxRemote(
            accountHandle: accountHandle,
            serverURL: serverURL,
            sandboxID: sandboxID,
            sandboxesService: sandboxesService
        )
        remote.onWait = { Self.note($0) }
        return remote
    }

    /// Progress notes go to stderr, so they never mix with a command's output on stdout.
    private static func note(_ message: String) {
        FileHandle.standardError.write(Data("tuist: \(message)\n".utf8))
    }

    /// Runs `cancel` on SIGINT or SIGTERM, then exits as the signal would have.
    private static func onInterrupt(_ cancel: @escaping @Sendable () async -> Void) -> [any DispatchSourceSignal] {
        [SIGINT, SIGTERM].map { signalNumber in
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .global())
            source.setEventHandler {
                Task {
                    await cancel()
                    exit(128 + signalNumber)
                }
            }
            source.setCancelHandler { signal(signalNumber, SIG_DFL) }
            source.resume()
            return source
        }
    }

    func transition(_ transition: SandboxTransition, options: SandboxOptions.Values, sandboxID: String) async throws {
        let (accountHandle, serverURL) = try await resolve(options)
        let (message, done) = switch transition {
        case .pause: ("Pausing sandbox...", "Sandbox \(sandboxID) is paused")
        case .resume: ("Resuming sandbox...", "Resumed sandbox \(sandboxID)")
        case .archive: ("Queuing the archive...", "Archive queued")
        }
        let sandbox = try await step(message, done: done, options: options) { () async throws -> ServerSandbox in
            do {
                return try await sandboxesService.transitionSandbox(
                    transition,
                    accountHandle: accountHandle,
                    serverURL: serverURL,
                    sandboxID: sandboxID
                )
            } catch let SandboxesServiceError.refused(reason) where transition == .pause {
                // The server refuses to pause a paused sandbox, such as one it paused itself after it went idle, but
                // that sandbox is already where the caller wants it.
                guard let sandbox = try? await sandboxesService.getSandbox(
                    accountHandle: accountHandle,
                    serverURL: serverURL,
                    sandboxID: sandboxID
                ), sandbox.state == .paused else { throw SandboxesServiceError.refused(reason) }
                return sandbox
            }
        }
        guard options.json || transition == .archive else { return }
        try output(sandbox, options: options) { sandbox in
            "Archiving sandbox \(sandbox.id). It stays paused until its disks are uploaded, then shows as archived."
        }
    }

    func delete(options: SandboxOptions.Values, sandboxID: String) async throws {
        let (accountHandle, serverURL) = try await resolve(options)
        try await step("Deleting sandbox...", done: "Deleted sandbox \(sandboxID)", options: options) {
            try await sandboxesService.deleteSandbox(accountHandle: accountHandle, serverURL: serverURL, sandboxID: sandboxID)
        }
        if options.json {
            try Noora.current.json(SandboxDeleted(id: sandboxID, deleted: true))
        }
    }

    private struct SandboxDeleted: Codable {
        let id: String
        let deleted: Bool
    }

    /// A spinner while the server works, which can take a while when it boots, restores or waits for a node.
    /// JSON output skips it so scripts read only the response.
    private func step<Value>(
        _ message: String,
        done: String,
        options: SandboxOptions.Values,
        show: Bool = true,
        _ work: @escaping () async throws -> Value
    ) async throws -> Value {
        guard show, !options.json else { return try await work() }
        return try await Noora.current.progressStep(
            message: message,
            successMessage: done,
            errorMessage: nil,
            showSpinner: true
        ) { _ in try await work() }
    }

    private func output<Value: Codable>(
        _ value: Value,
        options: SandboxOptions.Values,
        human: (Value) -> String
    ) throws {
        if options.json {
            try Noora.current.json(value)
        } else {
            Noora.current.passthrough("\(human(value))\n")
        }
    }

    /// The account from `--account`, falling back to the account in the project's full handle, and the server URL
    /// from the project's configuration.
    private func resolve(_ options: SandboxOptions.Values) async throws -> (String, URL) {
        let directory = try await Environment.current.pathRelativeToWorkingDirectory(options.path)
        let config = try await configLoader.loadConfig(path: directory)
        guard let accountHandle = try options.account
            ?? config.fullHandle.map({ try fullHandleService.parse($0).accountHandle }),
            !accountHandle.isEmpty
        else {
            throw SandboxCommandError.missingAccount
        }
        return (accountHandle, try serverEnvironmentService.url(configServerURL: config.url))
    }
}
