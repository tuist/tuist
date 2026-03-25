import Foundation
import Noora
import Path
import TuistConfigLoader
import TuistEnvironment
import TuistNooraExtension
import TuistServer

protocol TestListCommandServicing {
    func run(
        fullHandle: String?,
        path: String?,
        gitBranch: String?,
        status: String?,
        scheme: String?,
        page: Int?,
        pageSize: Int?,
        json: Bool
    ) async throws
}

enum TestListCommandServiceError: Equatable, LocalizedError {
    case missingFullHandle

    var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            return "We couldn't list test runs because the full handle is missing. You can pass either its value or a path to a Tuist project."
        }
    }
}

struct TestListCommandService: TestListCommandServicing {
    private let listTestRunsService: ListTestRunsServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        listTestRunsService: ListTestRunsServicing = ListTestRunsService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.listTestRunsService = listTestRunsService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(
        fullHandle: String?,
        path: String?,
        gitBranch: String?,
        status: String?,
        scheme: String?,
        page: Int?,
        pageSize: Int?,
        json: Bool
    ) async throws {
        let directoryPath: AbsolutePath = try await Environment.current.pathRelativeToWorkingDirectory(path)

        let config = try await configLoader.loadConfig(path: directoryPath)
        guard let resolvedFullHandle = fullHandle ?? config.fullHandle else {
            throw TestListCommandServiceError.missingFullHandle
        }

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        let startPage = (page ?? 1) - 1
        let resolvedPageSize = pageSize ?? 10

        let initialPage = try await listTestRunsService.listTestRuns(
            fullHandle: resolvedFullHandle,
            serverURL: serverURL,
            gitBranch: gitBranch,
            status: status,
            scheme: scheme,
            page: startPage + 1,
            pageSize: resolvedPageSize
        )

        let initialTestRuns = initialPage.test_runs

        if json {
            try Noora.current.json(initialTestRuns)
            return
        }

        if initialTestRuns.isEmpty {
            Noora.current.passthrough("No test runs found for project \(resolvedFullHandle).")
            return
        }

        let totalPages = initialPage.pagination_metadata.total_pages ?? 1

        let initialRows = initialTestRuns.map { Self.formatTestRunRow($0) }

        try await Noora.current.paginatedTable(
            headers: ["ID", "Status", "Scheme", "Duration", "Selective Testing", "Date"],
            pageSize: resolvedPageSize,
            totalPages: totalPages,
            startPage: startPage,
            loadPage: { [self] pageIndex in
                if pageIndex == startPage {
                    return initialRows
                }

                let page = try await listTestRunsService.listTestRuns(
                    fullHandle: resolvedFullHandle,
                    serverURL: serverURL,
                    gitBranch: gitBranch,
                    status: status,
                    scheme: scheme,
                    page: pageIndex + 1,
                    pageSize: resolvedPageSize
                )

                return page.test_runs.map { Self.formatTestRunRow($0) }
            }
        )
    }

    private static func formatTestRunRow(
        _ testRun: Operations.listTestRuns.Output.Ok.Body.jsonPayload.test_runsPayloadPayload
    ) -> [String] {
        let selectiveTesting: String
        if let targets = testRun.selective_testing_targets, targets > 0 {
            let hits = (testRun.selective_testing_local_hits ?? 0) + (testRun.selective_testing_remote_hits ?? 0)
            let pct = Int((Double(hits) / Double(targets) * 100).rounded())
            selectiveTesting = "\(pct)%"
        } else {
            selectiveTesting = "-"
        }

        return [
            testRun.id,
            testRun.status.rawValue,
            testRun.scheme ?? "-",
            Formatters.formatDuration(testRun.duration),
            selectiveTesting,
            testRun.ran_at.map { Formatters.formatDate($0) } ?? "-",
        ]
    }
}
