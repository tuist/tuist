import Foundation
import Noora
import TuistConfigLoader
import TuistEnvironment
import TuistHTTP
import TuistServer

enum SandboxCommandError: LocalizedError, Equatable {
    case missingAccount
    case commandFailed(exitCode: Int?)

    var errorDescription: String? {
        switch self {
        case .missingAccount:
            return "Pass --account or configure a project full handle."
        case let .commandFailed(exitCode):
            return exitCode.map { "The command exited with status \($0)." } ?? "The command was killed before it exited."
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

    init(
        configLoader: ConfigLoading = ConfigLoader(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        fullHandleService: FullHandleServicing = FullHandleService(),
        sandboxesService: SandboxesServicing = SandboxesService()
    ) {
        self.configLoader = configLoader
        self.serverEnvironmentService = serverEnvironmentService
        self.fullHandleService = fullHandleService
        self.sandboxesService = sandboxesService
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
            headers: ["ID", "Status", "vCPUs", "Memory", "Last active"],
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
        template: String?,
        vcpus: Int?,
        memoryMB: Int?,
        workspaceGB: Int?
    ) async throws {
        let (accountHandle, serverURL) = try await resolve(options)
        let sandbox = try await sandboxesService.createSandbox(
            accountHandle: accountHandle,
            serverURL: serverURL,
            template: template,
            vcpus: vcpus,
            memoryMB: memoryMB,
            workspaceGB: workspaceGB
        )
        try output(sandbox, options: options) { "Created sandbox \($0.id).\n\n" + SandboxOutput.details($0) }
    }

    /// Prints the command's output and fails with its exit status, so scripts can rely on it as on a local command.
    func exec(options: SandboxOptions.Values, sandboxID: String, command: String, timeoutMs: Int?) async throws {
        let (accountHandle, serverURL) = try await resolve(options)
        let result = try await sandboxesService.execSandboxCommand(
            accountHandle: accountHandle,
            serverURL: serverURL,
            sandboxID: sandboxID,
            command: command,
            timeoutMs: timeoutMs
        )
        if options.json {
            try Noora.current.json(result)
        } else {
            FileHandle.standardOutput.write(Data(result.stdout.utf8))
            FileHandle.standardError.write(Data(result.stderr.utf8))
        }
        guard result.exit_code == 0 else { throw SandboxCommandError.commandFailed(exitCode: result.exit_code) }
    }

    func transition(_ transition: SandboxTransition, options: SandboxOptions.Values, sandboxID: String) async throws {
        let (accountHandle, serverURL) = try await resolve(options)
        let sandbox = try await sandboxesService.transitionSandbox(
            transition,
            accountHandle: accountHandle,
            serverURL: serverURL,
            sandboxID: sandboxID
        )
        try output(sandbox, options: options) { sandbox in
            switch transition {
            case .pause: return "Paused sandbox \(sandbox.id)."
            case .resume: return "Resumed sandbox \(sandbox.id)."
            case .archive:
                return "Archiving sandbox \(sandbox.id). It stays paused until its disks are uploaded, then shows as archived."
            }
        }
    }

    func delete(options: SandboxOptions.Values, sandboxID: String) async throws {
        let (accountHandle, serverURL) = try await resolve(options)
        try await sandboxesService.deleteSandbox(accountHandle: accountHandle, serverURL: serverURL, sandboxID: sandboxID)
        if options.json {
            try Noora.current.json(SandboxDeleted(id: sandboxID, deleted: true))
        } else {
            Noora.current.success("Deleted sandbox \(sandboxID).")
        }
    }

    private struct SandboxDeleted: Codable {
        let id: String
        let deleted: Bool
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
