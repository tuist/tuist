import Foundation
import Noora
import Path
import TuistConfigLoader
import TuistEnvironment
import TuistNooraExtension
import TuistServer

protocol TestModuleListCommandServicing {
    func run(
        testRunId: String,
        fullHandle: String?,
        path: String?,
        status: String?,
        page: Int?,
        pageSize: Int?,
        json: Bool
    ) async throws
}

enum TestModuleListCommandServiceError: Equatable, LocalizedError {
    case missingFullHandle

    var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            return "We couldn't list test module runs because the full handle is missing. You can pass either its value or a path to a Tuist project."
        }
    }
}

struct TestModuleListCommandService: TestModuleListCommandServicing {
    private let listTestModuleRunsService: ListTestModuleRunsServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        listTestModuleRunsService: ListTestModuleRunsServicing = ListTestModuleRunsService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.listTestModuleRunsService = listTestModuleRunsService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(
        testRunId: String,
        fullHandle: String?,
        path: String?,
        status: String?,
        page: Int?,
        pageSize: Int?,
        json: Bool
    ) async throws {
        let directoryPath: AbsolutePath = try await Environment.current.pathRelativeToWorkingDirectory(path)

        let config = try await configLoader.loadConfig(path: directoryPath)
        guard let resolvedFullHandle = fullHandle ?? config.fullHandle else {
            throw TestModuleListCommandServiceError.missingFullHandle
        }

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        let startPage = (page ?? 1) - 1
        let resolvedPageSize = pageSize ?? 10

        let initialPage = try await listTestModuleRunsService.listTestModuleRuns(
            fullHandle: resolvedFullHandle,
            serverURL: serverURL,
            testRunId: testRunId,
            status: status,
            page: startPage + 1,
            pageSize: resolvedPageSize
        )

        let initialModules = initialPage.modules

        if json {
            try Noora.current.json(initialModules)
            return
        }

        if initialModules.isEmpty {
            Noora.current.passthrough("No module runs found for test run \(testRunId).")
            return
        }

        let totalPages = initialPage.pagination_metadata.total_pages ?? 1

        let initialRows = initialModules.map { module in
            [
                module.name,
                module.status.rawValue,
                Formatters.formatDuration(module.duration),
                module.test_case_count.map { "\($0)" } ?? "-",
                module.test_suite_count.map { "\($0)" } ?? "-",
            ]
        }

        try await Noora.current.paginatedTable(
            headers: ["Name", "Status", "Duration", "Tests", "Suites"],
            pageSize: resolvedPageSize,
            totalPages: totalPages,
            startPage: startPage,
            loadPage: { [self] pageIndex in
                if pageIndex == startPage {
                    return initialRows
                }

                let page = try await listTestModuleRunsService.listTestModuleRuns(
                    fullHandle: resolvedFullHandle,
                    serverURL: serverURL,
                    testRunId: testRunId,
                    status: status,
                    page: pageIndex + 1,
                    pageSize: resolvedPageSize
                )

                return page.modules.map { module in
                    [
                        module.name,
                        module.status.rawValue,
                        Formatters.formatDuration(module.duration),
                        module.test_case_count.map { "\($0)" } ?? "-",
                        module.test_suite_count.map { "\($0)" } ?? "-",
                    ]
                }
            }
        )
    }
}
