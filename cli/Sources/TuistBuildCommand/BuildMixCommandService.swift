import Foundation
import Noora
import TuistConfigLoader
import TuistNooraExtension
import TuistServer

struct BuildMixListCommandService {
    private let mixBuildsService: MixBuildsServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        mixBuildsService: MixBuildsServicing = MixBuildsService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.mixBuildsService = mixBuildsService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(
        fullHandle: String?,
        path: String?,
        gitBranch: String?,
        status: String?,
        mixEnv: String?,
        page: Int?,
        pageSize: Int?,
        json: Bool
    ) async throws {
        let context = try await BuildRunsContext.resolve(
            fullHandle: fullHandle,
            path: path,
            configLoader: configLoader,
            serverEnvironmentService: serverEnvironmentService
        )
        let startPage = (page ?? 1) - 1
        let pageSize = pageSize ?? 10

        let fetch = { (pageIndex: Int) in
            try await mixBuildsService.listMixBuilds(
                fullHandle: context.fullHandle,
                serverURL: context.serverURL,
                gitBranch: gitBranch,
                status: status,
                mixEnv: mixEnv,
                page: pageIndex + 1,
                pageSize: pageSize
            )
        }

        let initialPage = try await fetch(startPage)

        if json {
            try Noora.current.json(initialPage)
            return
        }

        if initialPage.builds.isEmpty {
            Noora.current.passthrough("No Mix builds found for project \(context.fullHandle).")
            return
        }

        try await Noora.current.paginatedTable(
            headers: ["ID", "Status", "Mix Env", "Branch", "Duration", "CI", "Created"],
            pageSize: pageSize,
            totalPages: initialPage.pagination_metadata.total_pages ?? 1,
            startPage: startPage,
            loadPage: { pageIndex in
                let page = pageIndex == startPage ? initialPage : try await fetch(pageIndex)
                return page.builds.map { build in
                    [
                        build.id,
                        build.status.rawValue,
                        build.mix_env ?? "-",
                        build.git_branch ?? "-",
                        Formatters.formatDuration(build.duration_ms),
                        BuildRunsContext.yesNo(build.is_ci),
                        Formatters.formatDate(build.inserted_at),
                    ]
                }
            }
        )
    }
}

struct BuildMixShowCommandService {
    private let mixBuildsService: MixBuildsServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        mixBuildsService: MixBuildsServicing = MixBuildsService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.mixBuildsService = mixBuildsService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(fullHandle: String?, buildId: String, path: String?, json: Bool) async throws {
        let context = try await BuildRunsContext.resolve(
            fullHandle: fullHandle,
            path: path,
            configLoader: configLoader,
            serverEnvironmentService: serverEnvironmentService
        )
        let build = try await mixBuildsService.getMixBuild(
            fullHandle: context.fullHandle,
            serverURL: context.serverURL,
            buildId: buildId
        )

        if json {
            try Noora.current.json(build)
            return
        }

        var info = [
            "Mix build".bold(),
            "ID: \(build.id)",
            "Status: \(build.status.rawValue)",
            "Duration: \(Formatters.formatDuration(build.duration_ms))",
            "CI: \(BuildRunsContext.yesNo(build.is_ci))",
        ]
        if let mixEnv = build.mix_env { info.append("Mix Env: \(mixEnv)") }
        if let elixirVersion = build.elixir_version { info.append("Elixir Version: \(elixirVersion)") }
        if let otpVersion = build.otp_version { info.append("OTP Version: \(otpVersion)") }
        if let gitBranch = build.git_branch { info.append("Git Branch: \(gitBranch)") }
        if let gitCommitSHA = build.git_commit_sha { info.append("Git Commit: \(gitCommitSHA)") }
        if let name = build.actor.name { info.append("Ran By: \(name)") }
        info.append("Errors: \(build.diagnostics_error_count)")
        info.append("Warnings: \(build.diagnostics_warning_count)")

        info.append("")
        info.append("Cache Statistics".bold())
        info.append("Hits: \(build.cache.hits) (local \(build.cache.local_hits), remote \(build.cache.remote_hits))")
        info.append("Misses: \(build.cache.misses)")
        info.append("Hit Rate: \(BuildRunsContext.percentage(build.cache.hit_rate))")
        if let savedDuration = build.cache.saved_duration_ms {
            info.append("Time Saved: \(Formatters.formatDuration(savedDuration))")
        }

        info.append("")
        info.append("Created: \(Formatters.formatDate(build.inserted_at))")
        Noora.current.passthrough("\(info.joined(separator: "\n"))")
    }
}
