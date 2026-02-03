import Foundation
import Noora
import Path
import TuistEnvironment
import TuistLoader
import TuistServer
import TuistSupport

protocol CacheRunListCommandServicing {
    func run(
        projectFullHandle: String?,
        path: String?,
        gitBranch: String?,
        json: Bool
    ) async throws
}

enum CacheRunListCommandServiceError: Equatable, LocalizedError {
    case missingFullHandle

    var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            return "We couldn't list cache runs because the full handle is missing. You can pass either its value or a path to a Tuist project."
        }
    }
}

struct CacheRunListCommandService: CacheRunListCommandServicing {
    private let listCacheRunsService: ListCacheRunsServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        listCacheRunsService: ListCacheRunsServicing = ListCacheRunsService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.listCacheRunsService = listCacheRunsService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(
        projectFullHandle: String?,
        path: String?,
        gitBranch: String?,
        json: Bool
    ) async throws {
        let directoryPath: AbsolutePath = try await Environment.current.pathRelativeToWorkingDirectory(path)

        let config = try await configLoader.loadConfig(path: directoryPath)
        guard let resolvedFullHandle = projectFullHandle ?? config.fullHandle else {
            throw CacheRunListCommandServiceError.missingFullHandle
        }

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        let pageSize = 10
        let startPage = 0

        let response = try await listCacheRunsService.listCacheRuns(
            fullHandle: resolvedFullHandle,
            serverURL: serverURL,
            gitBranch: gitBranch,
            gitCommitSha: nil,
            gitRef: nil,
            page: startPage + 1,
            pageSize: pageSize
        )

        if json {
            try Noora.current.json(response)
            return
        }

        let cacheRuns = response.cache_runs

        if cacheRuns.isEmpty {
            let branchFilter = gitBranch.map { " for branch '\($0)'" } ?? ""
            Noora.current.passthrough("No cache runs found for project \(resolvedFullHandle)\(branchFilter).")
            return
        }

        let totalPages = response.pagination_metadata.total_pages ?? 1

        let initialRows = cacheRuns.map { cacheRun in
            [
                "\(cacheRun.id)",
                "\(cacheRun.status)",
                "\(Formatters.formatDuration(cacheRun.duration))",
                cacheRun.is_ci ? "Yes" : "No",
                cacheRun.git_branch ?? "-",
                Formatters.formatTimestamp(cacheRun.ran_at),
                cacheRun.url,
            ]
        }

        try await Noora.current.paginatedTable(
            headers: ["ID", "Status", "Duration", "CI", "Branch", "Date", "URL"],
            pageSize: pageSize,
            totalPages: totalPages,
            startPage: startPage,
            loadPage: { [self] pageIndex in
                if pageIndex == startPage {
                    return initialRows
                }

                let pageResponse = try await listCacheRunsService.listCacheRuns(
                    fullHandle: resolvedFullHandle,
                    serverURL: serverURL,
                    gitBranch: gitBranch,
                    gitCommitSha: nil,
                    gitRef: nil,
                    page: pageIndex + 1,
                    pageSize: pageSize
                )

                return pageResponse.cache_runs.map { cacheRun in
                    [
                        "\(cacheRun.id)",
                        "\(cacheRun.status)",
                        "\(Formatters.formatDuration(cacheRun.duration))",
                        cacheRun.is_ci ? "Yes" : "No",
                        cacheRun.git_branch ?? "-",
                        Formatters.formatTimestamp(cacheRun.ran_at),
                        cacheRun.url,
                    ]
                }
            }
        )
    }
}
