import Foundation
import Noora
import TuistConfigLoader
import TuistNooraExtension
import TuistServer

struct BuildOnceListCommandService {
    private let onceRunsService: OnceRunsServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        onceRunsService: OnceRunsServicing = OnceRunsService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.onceRunsService = onceRunsService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(
        fullHandle: String?,
        path: String?,
        kind: String?,
        status: String?,
        gitBranch: String?,
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
            try await onceRunsService.listOnceRuns(
                fullHandle: context.fullHandle,
                serverURL: context.serverURL,
                kind: kind,
                status: status,
                gitBranch: gitBranch,
                page: pageIndex + 1,
                pageSize: pageSize
            )
        }

        let initialPage = try await fetch(startPage)

        if json {
            try Noora.current.json(initialPage)
            return
        }

        if initialPage.runs.isEmpty {
            Noora.current.passthrough("No Once runs found for project \(context.fullHandle).")
            return
        }

        try await Noora.current.paginatedTable(
            headers: ["Run ID", "Kind", "Command", "Status", "Branch", "Duration", "Cache Hit Rate"],
            pageSize: pageSize,
            totalPages: initialPage.pagination_metadata.total_pages ?? 1,
            startPage: startPage,
            loadPage: { pageIndex in
                let page = pageIndex == startPage ? initialPage : try await fetch(pageIndex)
                return page.runs.map { run in
                    [
                        run.run_id,
                        run.kind.rawValue,
                        run.command,
                        run.status.rawValue,
                        run.git_branch ?? "-",
                        Formatters.formatDuration(run.duration_ms),
                        BuildRunsContext.percentage(run.cache.hit_rate),
                    ]
                }
            }
        )
    }
}

struct BuildOnceShowCommandService {
    private let onceRunsService: OnceRunsServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        onceRunsService: OnceRunsServicing = OnceRunsService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.onceRunsService = onceRunsService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(fullHandle: String?, runId: String, path: String?, json: Bool) async throws {
        let context = try await BuildRunsContext.resolve(
            fullHandle: fullHandle,
            path: path,
            configLoader: configLoader,
            serverEnvironmentService: serverEnvironmentService
        )
        let run = try await onceRunsService.getOnceRun(
            fullHandle: context.fullHandle,
            serverURL: context.serverURL,
            runId: runId
        )

        if json {
            try Noora.current.json(run)
            return
        }

        Noora.current.passthrough("\(format(run))")
    }

    func format(_ run: Operations.getOnceRun.Output.Ok.Body.jsonPayload) -> String {
        var info = [
            "Once run".bold(),
            "Run ID: \(run.run_id)",
            "Kind: \(run.kind.rawValue)",
            "Command: \(run.command)",
            "Status: \(run.status.rawValue)",
            "Duration: \(Formatters.formatDuration(run.duration_ms))",
            "CI: \(BuildRunsContext.yesNo(run.is_ci))",
        ]
        if let exitStatus = run.exit_status { info.append("Exit Status: \(exitStatus)") }
        if let gitBranch = run.git_branch { info.append("Git Branch: \(gitBranch)") }
        if let gitRev = run.git_rev { info.append("Git Revision: \(gitRev)\(run.git_dirty ? " (dirty)" : "")") }
        if let hostClass = run.host_class { info.append("Host: \(hostClass)") }
        if let onceVersion = run.once_version { info.append("Once Version: \(onceVersion)") }

        info.append("")
        info.append("Actions".bold())
        info.append("Total: \(run.actions.total)")
        info.append("Cached: \(run.actions.cached)")
        info.append("Executed: \(run.actions.executed)")
        info.append("Failed: \(run.actions.failed)")

        info.append("")
        info.append("Cache Statistics".bold())
        info.append("Hits: \(run.cache.hits) of \(run.cache.total_lookups) lookups")
        info.append("Misses: \(run.cache.misses)")
        info.append("Hit Rate: \(BuildRunsContext.percentage(run.cache.hit_rate))")
        info.append("Downloaded: \(Formatters.formatBytes(run.cache.content_download_bytes))")
        info.append("Uploaded: \(Formatters.formatBytes(run.cache.content_upload_bytes))")

        if let tests = run.tests {
            info.append("")
            info.append("Tests".bold())
            info.append("Test Cases: \(tests.test_cases)")
            info.append("Passed: \(tests.passed)")
            info.append("Failed: \(tests.failed)")
            info.append("Skipped: \(tests.skipped)")
        }

        if let startedAt = run.started_at {
            info.append("")
            info.append("Started: \(Formatters.formatDate(startedAt))")
        }
        return info.joined(separator: "\n")
    }
}
