import Foundation
import Noora
import TuistConfigLoader
import TuistEnvironment
import TuistHTTP
import TuistServer

enum RunnerProfileOutput {
    static func saveCacheFrom(defaultBranch: Bool, branches: [String]) -> String {
        let labels = (defaultBranch ? ["Default branch"] : []) + branches
        return labels.isEmpty ? "No branches" : labels.joined(separator: ", ")
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
        let (accountHandle, serverURL) = try await RunnerAccount.resolve(
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
                RunnerProfileOutput.saveCacheFrom(
                    defaultBranch: profile.cache_writer_default_branch,
                    branches: profile.cache_writer_branches
                ),
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
    func run(
        name: String,
        defaultBranch: Bool,
        branches: [String],
        account: String?,
        path: String?,
        json: Bool
    ) async throws
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

    func run(
        name: String,
        defaultBranch: Bool,
        branches: [String],
        account: String?,
        path: String?,
        json: Bool
    ) async throws {
        let (accountHandle, serverURL) = try await RunnerAccount.resolve(
            account: account,
            path: path,
            configLoader: configLoader,
            serverEnvironmentService: serverEnvironmentService,
            fullHandleService: fullHandleService
        )
        let profile = try await updateRunnerProfileService.updateCacheWriterPolicy(
            accountHandle: accountHandle,
            serverURL: serverURL,
            profileName: name,
            defaultBranch: defaultBranch,
            branches: branches
        )
        if json {
            try Noora.current.json(profile)
            return
        }
        let saveCacheFrom = RunnerProfileOutput.saveCacheFrom(
            defaultBranch: profile.cache_writer_default_branch,
            branches: profile.cache_writer_branches
        )
        Noora.current.success("Profile \(profile.name) saves cache from: \(saveCacheFrom).")
    }
}
