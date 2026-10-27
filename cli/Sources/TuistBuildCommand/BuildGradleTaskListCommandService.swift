import Foundation
import Noora
import Path
import TuistConfigLoader
import TuistEnvironment
import TuistNooraExtension
import TuistServer

protocol BuildGradleTaskListCommandServicing {
    func run(
        fullHandle: String?,
        buildId: String,
        path: String?,
        outcome: String?,
        page: Int?,
        pageSize: Int?,
        json: Bool
    ) async throws
}

enum BuildGradleTaskListCommandServiceError: Equatable, LocalizedError {
    case missingFullHandle

    var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            return "We couldn't list the Gradle build tasks because the full handle is missing. You can pass either its value or a path to a Tuist project."
        }
    }
}

struct BuildGradleTaskListCommandService: BuildGradleTaskListCommandServicing {
    private let listGradleBuildTasksService: ListGradleBuildTasksServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        listGradleBuildTasksService: ListGradleBuildTasksServicing = ListGradleBuildTasksService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.listGradleBuildTasksService = listGradleBuildTasksService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(
        fullHandle: String?,
        buildId: String,
        path: String?,
        outcome: String?,
        page: Int?,
        pageSize: Int?,
        json: Bool
    ) async throws {
        let directoryPath: AbsolutePath = try await Environment.current.pathRelativeToWorkingDirectory(path)

        let config = try await configLoader.loadConfig(path: directoryPath)
        guard let resolvedFullHandle = fullHandle ?? config.fullHandle else {
            throw BuildGradleTaskListCommandServiceError.missingFullHandle
        }

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        let startPage = (page ?? 1) - 1
        let pageSize = pageSize ?? 10

        let initialPage = try await listGradleBuildTasksService.listGradleBuildTasks(
            fullHandle: resolvedFullHandle,
            serverURL: serverURL,
            buildId: buildId,
            outcome: outcome,
            cacheable: nil,
            page: startPage + 1,
            pageSize: pageSize
        )

        let tasks = initialPage.tasks

        if json {
            try Noora.current.json(tasks)
            return
        }

        if tasks.isEmpty {
            Noora.current.passthrough("No tasks found for Gradle build \(buildId).")
            return
        }

        let totalPages = initialPage.pagination_metadata.total_pages ?? 1

        let initialRows = tasks.map { task in
            [
                task.task_path,
                task.outcome.rawValue,
                task.cacheable == true ? "Yes" : "No",
                Formatters.formatDuration(task.duration_ms),
            ]
        }

        try await Noora.current.paginatedTable(
            headers: ["Task Path", "Outcome", "Cacheable", "Duration"],
            pageSize: pageSize,
            totalPages: totalPages,
            startPage: startPage,
            loadPage: { [self] pageIndex in
                if pageIndex == startPage {
                    return initialRows
                }
                let taskPage = try await listGradleBuildTasksService.listGradleBuildTasks(
                    fullHandle: resolvedFullHandle,
                    serverURL: serverURL,
                    buildId: buildId,
                    outcome: outcome,
                    cacheable: nil,
                    page: pageIndex + 1,
                    pageSize: pageSize
                )
                return taskPage.tasks.map { task in
                    [
                        task.task_path,
                        task.outcome.rawValue,
                        task.cacheable == true ? "Yes" : "No",
                        Formatters.formatDuration(task.duration_ms),
                    ]
                }
            }
        )
    }
}
