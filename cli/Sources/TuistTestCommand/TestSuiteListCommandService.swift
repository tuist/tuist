import Foundation
import Noora
import Path
import TuistConfigLoader
import TuistEnvironment
import TuistNooraExtension
import TuistServer

protocol TestSuiteListCommandServicing {
    func run(
        testRunId: String,
        fullHandle: String?,
        path: String?,
        status: String?,
        moduleName: String?,
        page: Int?,
        pageSize: Int?,
        json: Bool
    ) async throws
}

enum TestSuiteListCommandServiceError: Equatable, LocalizedError {
    case missingFullHandle

    var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            return "We couldn't list test suite runs because the full handle is missing. You can pass either its value or a path to a Tuist project."
        }
    }
}

struct TestSuiteListCommandService: TestSuiteListCommandServicing {
    private let listTestSuiteRunsService: ListTestSuiteRunsServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        listTestSuiteRunsService: ListTestSuiteRunsServicing = ListTestSuiteRunsService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.listTestSuiteRunsService = listTestSuiteRunsService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(
        testRunId: String,
        fullHandle: String?,
        path: String?,
        status: String?,
        moduleName: String?,
        page: Int?,
        pageSize: Int?,
        json: Bool
    ) async throws {
        let directoryPath: AbsolutePath = try await Environment.current.pathRelativeToWorkingDirectory(path)

        let config = try await configLoader.loadConfig(path: directoryPath)
        guard let resolvedFullHandle = fullHandle ?? config.fullHandle else {
            throw TestSuiteListCommandServiceError.missingFullHandle
        }

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        let startPage = (page ?? 1) - 1
        let resolvedPageSize = pageSize ?? 10

        let initialPage = try await listTestSuiteRunsService.listTestSuiteRuns(
            fullHandle: resolvedFullHandle,
            serverURL: serverURL,
            testRunId: testRunId,
            moduleName: moduleName,
            status: status,
            page: startPage + 1,
            pageSize: resolvedPageSize
        )

        let initialSuites = initialPage.suites

        if json {
            try Noora.current.json(initialSuites)
            return
        }

        if initialSuites.isEmpty {
            Noora.current.passthrough("No suite runs found for test run \(testRunId).")
            return
        }

        let totalPages = initialPage.pagination_metadata.total_pages ?? 1

        let initialRows = initialSuites.map { suite in
            [
                suite.name,
                suite.status.rawValue,
                Formatters.formatDuration(suite.duration),
                suite.test_case_count.map { "\($0)" } ?? "-",
            ]
        }

        try await Noora.current.paginatedTable(
            headers: ["Name", "Status", "Duration", "Tests"],
            pageSize: resolvedPageSize,
            totalPages: totalPages,
            startPage: startPage,
            loadPage: { [self] pageIndex in
                if pageIndex == startPage {
                    return initialRows
                }

                let page = try await listTestSuiteRunsService.listTestSuiteRuns(
                    fullHandle: resolvedFullHandle,
                    serverURL: serverURL,
                    testRunId: testRunId,
                    moduleName: moduleName,
                    status: status,
                    page: pageIndex + 1,
                    pageSize: resolvedPageSize
                )

                return page.suites.map { suite in
                    [
                        suite.name,
                        suite.status.rawValue,
                        Formatters.formatDuration(suite.duration),
                        suite.test_case_count.map { "\($0)" } ?? "-",
                    ]
                }
            }
        )
    }
}
