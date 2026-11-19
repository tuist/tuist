import Foundation
import Noora
import TuistConfigLoader
import TuistNooraExtension
import TuistServer

struct BuildBazelListCommandService {
    private let bazelInvocationsService: BazelInvocationsServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        bazelInvocationsService: BazelInvocationsServicing = BazelInvocationsService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.bazelInvocationsService = bazelInvocationsService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(
        fullHandle: String?,
        path: String?,
        gitBranch: String?,
        status: String?,
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
            try await bazelInvocationsService.listBazelInvocations(
                fullHandle: context.fullHandle,
                serverURL: context.serverURL,
                gitBranch: gitBranch,
                status: status,
                page: pageIndex + 1,
                pageSize: pageSize
            )
        }

        let initialPage = try await fetch(startPage)

        if json {
            try Noora.current.json(initialPage)
            return
        }

        if initialPage.invocations.isEmpty {
            Noora.current.passthrough("No Bazel invocations found for project \(context.fullHandle).")
            return
        }

        try await Noora.current.paginatedTable(
            headers: ["ID", "Command", "Status", "Branch", "Duration", "CI", "Started"],
            pageSize: pageSize,
            totalPages: initialPage.pagination_metadata.total_pages ?? 1,
            startPage: startPage,
            loadPage: { pageIndex in
                let page = pageIndex == startPage ? initialPage : try await fetch(pageIndex)
                return page.invocations.map { invocation in
                    [
                        invocation.invocation_id,
                        ([invocation.command] + invocation.target_patterns).joined(separator: " "),
                        invocation.status.rawValue,
                        invocation.git_branch.isEmpty ? "-" : invocation.git_branch,
                        Formatters.formatDuration(invocation.duration_ms),
                        BuildRunsContext.yesNo(invocation.is_ci),
                        Formatters.formatDate(invocation.started_at),
                    ]
                }
            }
        )
    }
}

struct BuildBazelShowCommandService {
    private let bazelInvocationsService: BazelInvocationsServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        bazelInvocationsService: BazelInvocationsServicing = BazelInvocationsService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.bazelInvocationsService = bazelInvocationsService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(fullHandle: String?, invocationId: String, path: String?, json: Bool) async throws {
        let context = try await BuildRunsContext.resolve(
            fullHandle: fullHandle,
            path: path,
            configLoader: configLoader,
            serverEnvironmentService: serverEnvironmentService
        )
        let invocation = try await bazelInvocationsService.getBazelInvocation(
            fullHandle: context.fullHandle,
            serverURL: context.serverURL,
            invocationId: invocationId
        )

        if json {
            try Noora.current.json(invocation)
            return
        }

        Noora.current.passthrough("\(details(of: invocation).joined(separator: "\n"))")
    }

    private func details(of invocation: Operations.getBazelInvocation.Output.Ok.Body.jsonPayload) -> [String] {
        var info = [
            "Bazel invocation".bold(),
            "ID: \(invocation.invocation_id)",
            "Command: \(invocation.command)",
            "Status: \(invocation.status.rawValue) (exit code \(invocation.exit_code))",
            "Duration: \(Formatters.formatDuration(invocation.duration_ms))",
            "CI: \(BuildRunsContext.yesNo(invocation.is_ci))",
        ]
        if !invocation.target_patterns.isEmpty {
            info.append("Targets: \(invocation.target_patterns.joined(separator: " "))")
        }
        if !invocation.bazel_version.isEmpty { info.append("Bazel Version: \(invocation.bazel_version)") }
        if !invocation.git_branch.isEmpty { info.append("Git Branch: \(invocation.git_branch)") }
        if !invocation.git_commit_sha.isEmpty { info.append("Git Commit: \(invocation.git_commit_sha)") }

        let cache = invocation.cache
        info.append("")
        info.append("Cache Statistics".bold())
        info.append("Hits: \(cache.hits)")
        info.append("Misses: \(cache.misses)")
        info.append("Hit Rate: \(BuildRunsContext.percentage(cache.hit_rate))")
        info.append("Downloaded: \(Formatters.formatBytes(cache.download_bytes))")
        info.append("Uploaded: \(Formatters.formatBytes(cache.upload_bytes))")

        let metrics = invocation.build_metrics
        info.append("")
        info.append("Build Metrics".bold())
        info.append("Actions Created: \(metrics.actions_created)")
        info.append("Actions Executed: \(metrics.actions_executed)")
        info.append("Targets Configured: \(metrics.targets_configured)")
        info.append("Packages Loaded: \(metrics.packages_loaded)")
        info.append("CPU Time: \(Formatters.formatDuration(metrics.cpu_time_ms))")

        if let criticalPath = invocation.critical_path, !criticalPath.actions.isEmpty {
            info.append("")
            info.append("Critical Path (\(Formatters.formatDuration(criticalPath.duration_ms)))".bold())
            for action in criticalPath.actions {
                info.append("\(Formatters.formatDuration(action.duration_ms))  \(action.description)")
            }
        }

        info.append("")
        info.append("Started: \(Formatters.formatDate(invocation.started_at))")
        info.append("Finished: \(Formatters.formatDate(invocation.finished_at))")

        if invocation.status == .failure {
            info.append("")
            info.append(
                "Inspect the failure with `tuist build bazel step list \(invocation.invocation_id) --status failure` and `tuist build bazel logs \(invocation.invocation_id)`."
            )
        }

        return info
    }
}

struct BuildBazelLogsCommandService {
    private let bazelInvocationsService: BazelInvocationsServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        bazelInvocationsService: BazelInvocationsServicing = BazelInvocationsService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.bazelInvocationsService = bazelInvocationsService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(fullHandle: String?, invocationId: String, path: String?, json: Bool) async throws {
        let context = try await BuildRunsContext.resolve(
            fullHandle: fullHandle,
            path: path,
            configLoader: configLoader,
            serverEnvironmentService: serverEnvironmentService
        )

        var logs: Operations.listBazelInvocationLogs.Output.Ok.Body.jsonPayload.logsPayload = []
        var page = 1
        while true {
            let response = try await bazelInvocationsService.listBazelInvocationLogs(
                fullHandle: context.fullHandle,
                serverURL: context.serverURL,
                invocationId: invocationId,
                page: page,
                pageSize: 100
            )
            logs.append(contentsOf: response.logs)
            guard response.pagination_metadata.has_next_page, !response.logs.isEmpty else { break }
            page += 1
        }

        if json {
            try Noora.current.json(logs)
            return
        }

        if logs.isEmpty {
            Noora.current.passthrough("No logs found for Bazel invocation \(invocationId).")
            return
        }

        Noora.current.passthrough("\(logs.map(\.message).joined())")
    }
}
