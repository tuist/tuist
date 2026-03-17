import Foundation
import Noora
import Path
import TuistConfigLoader
import TuistEnvironment
import TuistNooraExtension
import TuistServer

protocol BuildXcodeCacheTaskListCommandServicing {
    func run(
        fullHandle: String?,
        buildId: String,
        path: String?,
        status: String?,
        taskType: String?,
        page: Int?,
        pageSize: Int?,
        json: Bool
    ) async throws
}

enum BuildXcodeCacheTaskListCommandServiceError: Equatable, LocalizedError {
    case missingFullHandle

    var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            return "We couldn't list the build cache tasks because the full handle is missing. You can pass either its value or a path to a Tuist project."
        }
    }
}

struct BuildXcodeCacheTaskListCommandService: BuildXcodeCacheTaskListCommandServicing {
    private let listBuildCacheTasksService: ListBuildCacheTasksServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        listBuildCacheTasksService: ListBuildCacheTasksServicing = ListBuildCacheTasksService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.listBuildCacheTasksService = listBuildCacheTasksService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(
        fullHandle: String?,
        buildId: String,
        path: String?,
        status: String?,
        taskType: String?,
        page: Int?,
        pageSize: Int?,
        json: Bool
    ) async throws {
        let directoryPath: AbsolutePath = try await Environment.current.pathRelativeToWorkingDirectory(path)

        let config = try await configLoader.loadConfig(path: directoryPath)
        guard let resolvedFullHandle = fullHandle ?? config.fullHandle else {
            throw BuildXcodeCacheTaskListCommandServiceError.missingFullHandle
        }

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        let startPage = (page ?? 1) - 1
        let pageSize = pageSize ?? 10

        let initialPage = try await listBuildCacheTasksService.listBuildCacheTasks(
            fullHandle: resolvedFullHandle,
            serverURL: serverURL,
            buildId: buildId,
            status: status,
            type: taskType,
            page: startPage + 1,
            pageSize: pageSize
        )

        let tasks = initialPage.tasks

        if json {
            try Noora.current.json(tasks)
            return
        }

        if tasks.isEmpty {
            Noora.current.passthrough("No cache tasks found for build \(buildId).")
            return
        }

        let totalPages = initialPage.pagination_metadata.total_pages ?? 1

        let initialRows = tasks.map { task in
            [
                task.key,
                task.status.rawValue,
                task._type.rawValue,
                task.read_duration.map { Formatters.formatDuration(Int($0)) } ?? "-",
            ]
        }

        try await Noora.current.paginatedTable(
            headers: ["Name", "Status", "Type", "Duration"],
            pageSize: pageSize,
            totalPages: totalPages,
            startPage: startPage,
            loadPage: { [self] pageIndex in
                if pageIndex == startPage {
                    return initialRows
                }
                let taskPage = try await listBuildCacheTasksService.listBuildCacheTasks(
                    fullHandle: resolvedFullHandle,
                    serverURL: serverURL,
                    buildId: buildId,
                    status: status,
                    type: taskType,
                    page: pageIndex + 1,
                    pageSize: pageSize
                )
                return taskPage.tasks.map { task in
                    [
                        task.key,
                        task.status.rawValue,
                        task._type.rawValue,
                        task.read_duration.map { Formatters.formatDuration(Int($0)) } ?? "-",
                    ]
                }
            }
        )
    }
}
