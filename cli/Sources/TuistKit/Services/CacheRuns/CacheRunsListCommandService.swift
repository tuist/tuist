import Foundation
import Noora
import Path
import TuistLoader
import TuistServer
import TuistSupport

protocol CacheRunsListCommandServicing {
    func run(
        project: String?,
        path: String?,
        gitBranch: String?,
        gitCommitSHA: String?,
        gitRef: String?,
        json: Bool
    ) async throws
}

enum CacheRunsListCommandServiceError: Equatable, LocalizedError {
    case missingFullHandle

    var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            return "We couldn't list cache runs because the full handle is missing. You can pass either its value or a path to a Tuist project."
        }
    }
}

final class CacheRunsListCommandService: CacheRunsListCommandServicing {
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
        gitCommitSHA: String?,
        gitRef: String?,
        json: Bool
    ) async throws {
        let directoryPath: AbsolutePath = try await Environment.current.pathRelativeToWorkingDirectory(path)

        let config = try await configLoader.loadConfig(path: directoryPath)
        guard let resolvedFullHandle = project != nil ? project! : config.fullHandle else {
            throw CacheRunsListCommandServiceError.missingFullHandle
        }

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        let response = try await listCacheRunsService.listCacheRuns(
            fullHandle: resolvedFullHandle,
            gitBranch: gitBranch,
            gitCommitSHA: gitCommitSHA,
            gitRef: gitRef,
            page: nil,
            pageSize: 50,
            serverURL: serverURL
        )

        if json {
            try Noora.current.json(response)
            return
        }

        if response.runs.isEmpty {
            Noora.current.passthrough("No cache runs found for project \(resolvedFullHandle).")
            return
        }

        try Noora.current.paginatedTable(TableData(columns: [
            TableColumn(title: "ID", width: .auto),
            TableColumn(title: "Duration (ms)", width: .auto),
            TableColumn(title: "Status", width: .auto),
            TableColumn(title: "Ran at", width: .auto),
            TableColumn(title: "URL", width: .auto),
        ], rows: response.runs.map { run in
            return [
                "\(run.id)",
                "\(run.duration)",
                "\(run.status)",
                "\(Formatters.formatDate(Date(timeIntervalSince1970: TimeInterval(run.ran_at))))",
                "\(.link(title: "Link", href: run.url))",
            ]
        }), pageSize: 10)
    }
}
