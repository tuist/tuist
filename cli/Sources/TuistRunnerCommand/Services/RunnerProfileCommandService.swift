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

    static func shape(vcpus: Int, memoryGB: Int, xcodeVersion: String?) -> String {
        let shape = "\(vcpus) vCPU, \(memoryGB) GB"
        return xcodeVersion.map { "\(shape), Xcode \($0)" } ?? shape
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
            Noora.current.passthrough("No runner profiles found.\n")
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

protocol RunnerProfileCatalogCommandServicing {
    func run(account: String?, path: String?, json: Bool) async throws
}

struct RunnerProfileCatalogCommandService: RunnerProfileCatalogCommandServicing {
    private let configLoader: ConfigLoading
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let fullHandleService: FullHandleServicing
    private let getRunnerCatalogService: GetRunnerCatalogServicing

    init(
        configLoader: ConfigLoading = ConfigLoader(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        fullHandleService: FullHandleServicing = FullHandleService(),
        getRunnerCatalogService: GetRunnerCatalogServicing = GetRunnerCatalogService()
    ) {
        self.configLoader = configLoader
        self.serverEnvironmentService = serverEnvironmentService
        self.fullHandleService = fullHandleService
        self.getRunnerCatalogService = getRunnerCatalogService
    }

    func run(account: String?, path: String?, json: Bool) async throws {
        let (accountHandle, serverURL) = try await RunnerAccount.resolve(
            account: account,
            path: path,
            configLoader: configLoader,
            serverEnvironmentService: serverEnvironmentService,
            fullHandleService: fullHandleService
        )
        let response = try await getRunnerCatalogService.getRunnerCatalog(
            accountHandle: accountHandle,
            serverURL: serverURL
        )
        if json {
            try Noora.current.json(response)
            return
        }
        let rows = response.shapes.map { shape in
            [
                shape.platform == .macos ? "macOS" : "Linux",
                String(shape.vcpus),
                "\(shape.memory_gb) GB",
                shape._default ? "✓" : "",
            ]
        }
        try await Noora.current.paginatedTable(
            headers: ["Platform", "vCPU", "RAM", "Default"],
            pageSize: max(rows.count, 1),
            totalPages: 1,
            startPage: 0,
            loadPage: { _ in rows }
        )
        let xcodeVersions = response.xcode_versions.map { $0._default ? "\($0.xcode_version) (default)" : $0.xcode_version }
        if !xcodeVersions.isEmpty {
            Noora.current.passthrough("Xcode versions for macOS profiles: \(xcodeVersions.joined(separator: ", ")).\n")
        }
    }
}

protocol RunnerProfileCreateCommandServicing {
    func run(
        name: String,
        platform: RunnerProfilePlatform,
        vcpus: Int,
        memoryGB: Int,
        xcodeVersion: String?,
        saveCacheFromDefaultBranch: Bool?,
        saveCacheFromBranches: [String]?,
        account: String?,
        path: String?,
        json: Bool
    ) async throws
}

struct RunnerProfileCreateCommandService: RunnerProfileCreateCommandServicing {
    private let configLoader: ConfigLoading
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let fullHandleService: FullHandleServicing
    private let createRunnerProfileService: CreateRunnerProfileServicing

    init(
        configLoader: ConfigLoading = ConfigLoader(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        fullHandleService: FullHandleServicing = FullHandleService(),
        createRunnerProfileService: CreateRunnerProfileServicing = CreateRunnerProfileService()
    ) {
        self.configLoader = configLoader
        self.serverEnvironmentService = serverEnvironmentService
        self.fullHandleService = fullHandleService
        self.createRunnerProfileService = createRunnerProfileService
    }

    func run(
        name: String,
        platform: RunnerProfilePlatform,
        vcpus: Int,
        memoryGB: Int,
        xcodeVersion: String?,
        saveCacheFromDefaultBranch: Bool?,
        saveCacheFromBranches: [String]?,
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
        let profile = try await createRunnerProfileService.createRunnerProfile(
            accountHandle: accountHandle,
            serverURL: serverURL,
            name: name,
            platform: platform,
            vcpus: vcpus,
            memoryGB: memoryGB,
            xcodeVersion: xcodeVersion,
            saveCacheFromDefaultBranch: saveCacheFromDefaultBranch,
            saveCacheFromBranches: saveCacheFromBranches
        )
        if json {
            try Noora.current.json(profile)
            return
        }
        let shape = RunnerProfileOutput.shape(
            vcpus: profile.vcpus,
            memoryGB: profile.memory_gb,
            xcodeVersion: profile.xcode_version
        )
        Noora.current.success(
            .alert(
                "Profile \(profile.name) created with \(shape).",
                takeaways: ["Run jobs on it with \(.command("runs-on: \(profile.runs_on_label)"))"]
            )
        )
    }
}

protocol RunnerProfileUpdateCommandServicing {
    func run(name: String, changes: RunnerProfileChanges, account: String?, path: String?, json: Bool) async throws
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

    func run(name: String, changes: RunnerProfileChanges, account: String?, path: String?, json: Bool) async throws {
        let (accountHandle, serverURL) = try await RunnerAccount.resolve(
            account: account,
            path: path,
            configLoader: configLoader,
            serverEnvironmentService: serverEnvironmentService,
            fullHandleService: fullHandleService
        )
        let profile = try await updateRunnerProfileService.updateRunnerProfile(
            accountHandle: accountHandle,
            serverURL: serverURL,
            profileName: name,
            changes: changes
        )
        if json {
            try Noora.current.json(profile)
            return
        }
        let shape = RunnerProfileOutput.shape(
            vcpus: profile.vcpus,
            memoryGB: profile.memory_gb,
            xcodeVersion: profile.xcode_version
        )
        let saveCacheFrom = RunnerProfileOutput.saveCacheFrom(
            defaultBranch: profile.cache_writer_default_branch,
            branches: profile.cache_writer_branches
        )
        Noora.current.success("Profile \(profile.name) runs on \(shape) and saves cache from: \(saveCacheFrom).")
    }
}

protocol RunnerProfileDeleteCommandServicing {
    func run(name: String, account: String?, path: String?, json: Bool) async throws
}

struct RunnerProfileDeleteCommandService: RunnerProfileDeleteCommandServicing {
    private let configLoader: ConfigLoading
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let fullHandleService: FullHandleServicing
    private let deleteRunnerProfileService: DeleteRunnerProfileServicing

    init(
        configLoader: ConfigLoading = ConfigLoader(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        fullHandleService: FullHandleServicing = FullHandleService(),
        deleteRunnerProfileService: DeleteRunnerProfileServicing = DeleteRunnerProfileService()
    ) {
        self.configLoader = configLoader
        self.serverEnvironmentService = serverEnvironmentService
        self.fullHandleService = fullHandleService
        self.deleteRunnerProfileService = deleteRunnerProfileService
    }

    func run(name: String, account: String?, path: String?, json: Bool) async throws {
        let (accountHandle, serverURL) = try await RunnerAccount.resolve(
            account: account,
            path: path,
            configLoader: configLoader,
            serverEnvironmentService: serverEnvironmentService,
            fullHandleService: fullHandleService
        )
        try await deleteRunnerProfileService.deleteRunnerProfile(
            accountHandle: accountHandle,
            serverURL: serverURL,
            profileName: name
        )
        if json {
            try Noora.current.json(["name": name])
        } else {
            Noora.current.success("Profile \(name) deleted.")
        }
    }
}
