import Foundation
import Noora
import TuistConfigLoader
import TuistEnvironment
import TuistHTTP
import TuistServer

enum RunnerProfileCommandServiceError: LocalizedError, Equatable {
    case missingAccount

    var errorDescription: String? {
        "Pass --account or configure a project full handle."
    }
}

enum RunnerProfileOutput {
    static func saveCacheFrom(_ branches: [String]?) -> String {
        switch branches {
        case nil: "Default branch"
        case let branches? where branches.isEmpty: "No branches"
        case let branches?: branches.joined(separator: ", ")
        }
    }
}

protocol RunnerProfileListCommandServicing {
    func run(account: String?, path: String?, json: Bool) async throws
}

struct RunnerProfileListCommandService: RunnerProfileListCommandServicing {
    private let configLoader: ConfigLoading
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let fullHandleService: FullHandleServicing
    private let listRunnerProfilesService: ListRunnerProfilesServicing

    init(
        configLoader: ConfigLoading = ConfigLoader(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        fullHandleService: FullHandleServicing = FullHandleService(),
        listRunnerProfilesService: ListRunnerProfilesServicing = ListRunnerProfilesService()
    ) {
        self.configLoader = configLoader
        self.serverEnvironmentService = serverEnvironmentService
        self.fullHandleService = fullHandleService
        self.listRunnerProfilesService = listRunnerProfilesService
    }

    func run(account: String?, path: String?, json: Bool) async throws {
        let (accountHandle, serverURL) = try await resolveAccount(
            account: account,
            path: path,
            configLoader: configLoader,
            serverEnvironmentService: serverEnvironmentService,
            fullHandleService: fullHandleService
        )
        let response = try await listRunnerProfilesService.listRunnerProfiles(
            accountHandle: accountHandle,
            serverURL: serverURL
        )
        if json {
            try Noora.current.json(response)
            return
        }
        guard !response.profiles.isEmpty else {
            Noora.current.passthrough("No runner profiles found.")
            return
        }
        let rows = response.profiles.map { profile in
            [
                profile.name,
                profile.platform == .macos ? "macOS" : "Linux",
                String(profile.vcpus),
                "\(profile.memory_gb) GB",
                RunnerProfileOutput.saveCacheFrom(profile.cache_writer_branches),
            ]
        }
        try await Noora.current.paginatedTable(
            headers: ["Name", "Platform", "vCPU", "RAM", "Save cache from"],
            pageSize: rows.count,
            totalPages: 1,
            startPage: 0,
            loadPage: { _ in rows }
        )
    }
}

protocol RunnerProfileUpdateCommandServicing {
    func run(name: String, branches: [String]?, account: String?, path: String?, json: Bool) async throws
}

struct RunnerProfileUpdateCommandService: RunnerProfileUpdateCommandServicing {
    private let configLoader: ConfigLoading
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let fullHandleService: FullHandleServicing
    private let updateRunnerProfileService: UpdateRunnerProfileServicing

    init(
        configLoader: ConfigLoading = ConfigLoader(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        fullHandleService: FullHandleServicing = FullHandleService(),
        updateRunnerProfileService: UpdateRunnerProfileServicing = UpdateRunnerProfileService()
    ) {
        self.configLoader = configLoader
        self.serverEnvironmentService = serverEnvironmentService
        self.fullHandleService = fullHandleService
        self.updateRunnerProfileService = updateRunnerProfileService
    }

    func run(name: String, branches: [String]?, account: String?, path: String?, json: Bool) async throws {
        let (accountHandle, serverURL) = try await resolveAccount(
            account: account,
            path: path,
            configLoader: configLoader,
            serverEnvironmentService: serverEnvironmentService,
            fullHandleService: fullHandleService
        )
        let profile = try await updateRunnerProfileService.updateCacheWriterBranches(
            accountHandle: accountHandle,
            serverURL: serverURL,
            profileName: name,
            branches: branches
        )
        if json {
            try Noora.current.json(profile)
            return
        }
        if let branches = profile.cache_writer_branches {
            Noora.current.success("Profile \(profile.name) saves cache from \(branches.joined(separator: ", ")).")
        } else {
            Noora.current.success("Profile \(profile.name) saves cache from each repository's default branch.")
        }
    }
}

private func resolveAccount(
    account: String?,
    path: String?,
    configLoader: ConfigLoading,
    serverEnvironmentService: ServerEnvironmentServicing,
    fullHandleService: FullHandleServicing
) async throws -> (String, URL) {
    let directory = try await Environment.current.pathRelativeToWorkingDirectory(path)
    let config = try await configLoader.loadConfig(path: directory)
    guard let accountHandle = try account ?? config.fullHandle.map({ try fullHandleService.parse($0).accountHandle }),
          !accountHandle.isEmpty
    else {
        throw RunnerProfileCommandServiceError.missingAccount
    }
    return (accountHandle, try serverEnvironmentService.url(configServerURL: config.url))
}
