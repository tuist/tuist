import Foundation
import Noora
import Path
import TuistConfigLoader
import TuistEnvironment
import TuistNooraExtension
import TuistServer

protocol TestCaseRunListCommandServicing {
    func run(
        project: String?,
        path: String?,
        testCaseIdentifier: String,
        flaky: Bool,
        page: Int?,
        pageSize: Int?,
        json: Bool
    ) async throws
}

enum TestCaseRunListCommandServiceError: Equatable, LocalizedError {
    case missingFullHandle

    var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            return "We couldn't list test case runs because the project is missing. You can pass either its value or a path to a Tuist project."
        }
    }
}

struct TestCaseRunListCommandService: TestCaseRunListCommandServicing {
    private let getTestCaseService: GetTestCaseServicing
    private let listTestCaseRunsService: ListTestCaseRunsServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        getTestCaseService: GetTestCaseServicing = GetTestCaseService(),
        listTestCaseRunsService: ListTestCaseRunsServicing = ListTestCaseRunsService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.getTestCaseService = getTestCaseService
        self.listTestCaseRunsService = listTestCaseRunsService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(
        project: String?,
        path: String?,
        testCaseIdentifier: String,
        flaky: Bool,
        page: Int?,
        pageSize: Int?,
        json: Bool
    ) async throws {
        let directoryPath: AbsolutePath = try await Environment.current.pathRelativeToWorkingDirectory(path)

        let config = try await configLoader.loadConfig(path: directoryPath)
        guard let resolvedFullHandle = project ?? config.fullHandle else {
            throw TestCaseRunListCommandServiceError.missingFullHandle
        }

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        let testCaseId: String
        switch try TestCaseIdentifier(testCaseIdentifier) {
        case let .name(moduleName, suiteName, testName):
            let testCase = try await getTestCaseService.getTestCaseByName(
                fullHandle: resolvedFullHandle,
                moduleName: moduleName,
                name: testName,
                suiteName: suiteName,
                serverURL: serverURL
            )
            testCaseId = testCase.id
        case let .id(id):
            testCaseId = id
        }

        let pageSize = pageSize ?? 10
        let startPage = (page ?? 1) - 1

        let initialPage = try await listTestCaseRunsService.listTestCaseRuns(
            fullHandle: resolvedFullHandle,
            serverURL: serverURL,
            testCaseId: testCaseId,
            flaky: flaky ? true : nil,
            page: startPage + 1,
            pageSize: pageSize
        )

        let initialRuns = initialPage.test_case_runs

        if json {
            try Noora.current.json(initialRuns)
            return
        }

        if initialRuns.isEmpty {
            var message = "No test case runs found for \(testCaseIdentifier)"
            if flaky { message += " (flaky only)" }
            Noora.current.passthrough(TerminalText(stringLiteral: message + "."))
            return
        }

        let totalPages = initialPage.pagination_metadata.total_pages ?? 1

        let initialRows = initialRuns.map { formatRunRow($0) }

        try await Noora.current.paginatedTable(
            headers: ["Status", "Duration", "CI", "Flaky", "Branch", "Commit", "Ran At"],
            pageSize: pageSize,
            totalPages: totalPages,
            startPage: startPage,
            loadPage: { [self] pageIndex in
                if pageIndex == startPage {
                    return initialRows
                }

                let runsPage = try await listTestCaseRunsService.listTestCaseRuns(
                    fullHandle: resolvedFullHandle,
                    serverURL: serverURL,
                    testCaseId: testCaseId,
                    flaky: flaky ? true : nil,
                    page: pageIndex + 1,
                    pageSize: pageSize
                )

                return runsPage.test_case_runs.map { formatRunRow($0) }
            }
        )
    }

    private func formatRunRow(_ run: Operations.listTestCaseRuns.Output.Ok.Body.jsonPayload
        .test_case_runsPayloadPayload) -> [String]
    {
        [
            run.status.rawValue,
            Formatters.formatDuration(run.duration),
            run.is_ci ? "Yes" : "No",
            run.is_flaky ? "Yes" : "No",
            run.git_branch ?? "-",
            run.git_commit_sha.map { String($0.prefix(7)) } ?? "-",
            run.ran_at.map { Formatters.formatTimestamp($0) } ?? "-",
        ]
    }
}
