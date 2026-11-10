import Foundation
import Noora
import TuistConfigLoader
import TuistNooraExtension
import TuistServer

struct BuildCargoListCommandService {
    private let cargoBuildsService: CargoBuildsServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        cargoBuildsService: CargoBuildsServicing = CargoBuildsService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.cargoBuildsService = cargoBuildsService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(
        fullHandle: String?,
        path: String?,
        gitBranch: String?,
        status: String?,
        command: String?,
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
            try await cargoBuildsService.listCargoBuilds(
                fullHandle: context.fullHandle,
                serverURL: context.serverURL,
                gitBranch: gitBranch,
                status: status,
                command: command,
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
            Noora.current.passthrough("No Cargo builds found for project \(context.fullHandle).")
            return
        }

        try await Noora.current.paginatedTable(
            headers: ["ID", "Command", "Status", "Branch", "Duration", "CI", "Created"],
            pageSize: pageSize,
            totalPages: initialPage.pagination_metadata.total_pages ?? 1,
            startPage: startPage,
            loadPage: { pageIndex in
                let page = pageIndex == startPage ? initialPage : try await fetch(pageIndex)
                return page.builds.map { build in
                    [
                        build.id,
                        build.command ?? "-",
                        build.status.rawValue,
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

struct BuildCargoShowCommandService {
    private let cargoBuildsService: CargoBuildsServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        cargoBuildsService: CargoBuildsServicing = CargoBuildsService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.cargoBuildsService = cargoBuildsService
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
        let build = try await cargoBuildsService.getCargoBuild(
            fullHandle: context.fullHandle,
            serverURL: context.serverURL,
            buildId: buildId
        )

        if json {
            try Noora.current.json(build)
            return
        }

        var info = [
            "Cargo build".bold(),
            "ID: \(build.id)",
            "Command: \(build.command ?? "-")",
            "Status: \(build.status.rawValue)",
            "Duration: \(Formatters.formatDuration(build.duration_ms))",
            "CI: \(BuildRunsContext.yesNo(build.is_ci))",
        ]
        if let rustVersion = build.rust_version { info.append("Rust Version: \(rustVersion)") }
        if let gitBranch = build.git_branch { info.append("Git Branch: \(gitBranch)") }
        if let gitCommitSHA = build.git_commit_sha { info.append("Git Commit: \(gitCommitSHA)") }
        if let name = build.actor.name { info.append("Ran By: \(name)") }

        info.append("")
        info.append("Cache Statistics".bold())
        if let cache = build.cache {
            info.append("Hits: \(cache.hits)")
            info.append("Task Misses: \(cache.task_misses)")
            info.append("Hit Rate: \(BuildRunsContext.percentage(cache.hit_rate))")
            info.append("Downloaded: \(Formatters.formatBytes(cache.downloaded_bytes))")
            info.append("Uploaded: \(Formatters.formatBytes(cache.uploaded_bytes))")
        } else {
            info.append("The build reported no cache measurements.")
        }

        info.append("")
        info.append("Created: \(Formatters.formatDate(build.inserted_at))")
        Noora.current.passthrough("\(info.joined(separator: "\n"))")
    }
}
