import Foundation
import Noora
import OpenAPIURLSession
import Path
import TuistLoader
import TuistServer
import TuistSupport

protocol CacheRunListCommandServicing {
    func run(
        project: String?,
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

final class CacheRunListCommandService: CacheRunListCommandServicing {
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
        project: String?,
        path: String?,
        gitBranch: String?,
        json: Bool
    ) async throws {
        let directoryPath: AbsolutePath = try await Environment.current.pathRelativeToWorkingDirectory(path)

        let config = try await configLoader.loadConfig(path: directoryPath)
        guard let resolvedFullHandle = project != nil ? project! : config.fullHandle else {
            throw CacheRunListCommandServiceError.missingFullHandle
        }

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        let response = try await listCacheRunsService.listCacheRuns(
            fullHandle: resolvedFullHandle,
            serverURL: serverURL,
            gitBranch: gitBranch,
            gitCommitSha: nil,
            gitRef: nil,
            page: nil,
            pageSize: 50
        )

        if json {
            try Noora.current.json(response)
            return
        }

        if response.cache_runs.isEmpty {
            let branchFilter = gitBranch.map { " for branch '\($0)'" } ?? ""
            Noora.current.passthrough("No cache runs found for project \(resolvedFullHandle)\(branchFilter).")
            return
        }

        try Noora.current.paginatedTable(TableData(columns: [
            TableColumn(title: "ID", width: .auto),
            TableColumn(title: "Status", width: .auto),
            TableColumn(title: "Duration", width: .auto),
            TableColumn(title: "CI", width: .auto),
            TableColumn(title: "Branch", width: .auto),
            TableColumn(title: "Date", width: .auto),
            TableColumn(title: "URL", width: .auto),
        ], rows: response.cache_runs.map { cacheRun in
            return [
                "\(cacheRun.id)",
                "\(cacheRun.status)",
                "\(Formatters.formatDuration(cacheRun.duration))",
                "\(cacheRun.is_ci ? "Yes" : "No")",
                "\(cacheRun.git_branch ?? "-")",
                "\(Formatters.formatTimestamp(cacheRun.ran_at))",
                "\(.link(title: "Link", href: cacheRun.url))",
            ]
        }), pageSize: 10)
    }
}
