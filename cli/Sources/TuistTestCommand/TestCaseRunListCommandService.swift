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
        testCaseIdentifier: String?,
        flaky: Bool,
        testRunId: String?,
        page: Int?,
        pageSize: Int?,
        json: Bool
    ) async throws
}

enum TestCaseRunListCommandServiceError: Equatable, LocalizedError {
    case missingFullHandle
    case missingIdentifier

    var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            return "We couldn't list test case runs because the project is missing. You can pass either its value or a path to a Tuist project."
        case .missingIdentifier:
            return "You must provide either a test case identifier or a --test-run-id."
        }
    }
}

struct TestCaseRunListCommandService: TestCaseRunListCommandServicing {
    private let getTestCaseService: GetTestCaseServicing
    private let listTestCaseRunsService: ListTestCaseRunsServicing
    private let listTestCaseRunsByTestRunService: ListTestCaseRunsByTestRunServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        getTestCaseService: GetTestCaseServicing = GetTestCaseService(),
        listTestCaseRunsService: ListTestCaseRunsServicing = ListTestCaseRunsService(),
        listTestCaseRunsByTestRunService: ListTestCaseRunsByTestRunServicing = ListTestCaseRunsByTestRunService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.getTestCaseService = getTestCaseService
        self.listTestCaseRunsService = listTestCaseRunsService
        self.listTestCaseRunsByTestRunService = listTestCaseRunsByTestRunService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(
        project: String?,
        path: String?,
        testCaseIdentifier: String?,
        flaky: Bool,
        testRunId: String?,
        page: Int?,
        pageSize: Int?,
        json: Bool
    ) async throws {
        guard testCaseIdentifier != nil || testRunId != nil else {
            throw TestCaseRunListCommandServiceError.missingIdentifier
        }

        let directoryPath: AbsolutePath = try await Environment.current.pathRelativeToWorkingDirectory(path)

        let config = try await configLoader.loadConfig(path: directoryPath)
        guard let resolvedFullHandle = project ?? config.fullHandle else {
            throw TestCaseRunListCommandServiceError.missingFullHandle
        }

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        let pageSize = pageSize ?? 10
        let startPage = (page ?? 1) - 1

        if let testCaseIdentifier {
            try await runByTestCase(
                testCaseIdentifier: testCaseIdentifier,
                flaky: flaky,
                testRunId: testRunId,
                fullHandle: resolvedFullHandle,
                serverURL: serverURL,
                pageSize: pageSize,
                startPage: startPage,
                json: json
            )
        } else if let testRunId {
            try await runByTestRun(
                testRunId: testRunId,
                fullHandle: resolvedFullHandle,
                serverURL: serverURL,
                pageSize: pageSize,
                startPage: startPage,
                json: json
            )
        }
    }

    private func runByTestCase(
        testCaseIdentifier: String,
        flaky: Bool,
        testRunId: String?,
        fullHandle: String,
        serverURL: URL,
        pageSize: Int,
        startPage: Int,
        json: Bool
    ) async throws {
        let testCaseId: String
        switch try TestCaseIdentifier(testCaseIdentifier) {
        case let .name(moduleName, suiteName, testName):
            let testCase = try await getTestCaseService.getTestCaseByName(
                fullHandle: fullHandle,
                moduleName: moduleName,
                name: testName,
                suiteName: suiteName,
                serverURL: serverURL
            )
            testCaseId = testCase.id
        case let .id(id):
            testCaseId = id
        }

        let initialPage = try await listTestCaseRunsService.listTestCaseRuns(
            fullHandle: fullHandle,
            serverURL: serverURL,
            testCaseId: testCaseId,
            flaky: flaky ? true : nil,
            testRunId: testRunId,
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
            headers: ["ID", "Status", "Duration", "CI", "Flaky", "Branch", "Commit", "Ran At"],
            pageSize: pageSize,
            totalPages: totalPages,
            startPage: startPage,
            loadPage: { [self] pageIndex in
                if pageIndex == startPage {
                    return initialRows
                }

                let runsPage = try await listTestCaseRunsService.listTestCaseRuns(
                    fullHandle: fullHandle,
                    serverURL: serverURL,
                    testCaseId: testCaseId,
                    flaky: flaky ? true : nil,
                    testRunId: testRunId,
                    page: pageIndex + 1,
                    pageSize: pageSize
                )

                return runsPage.test_case_runs.map { formatRunRow($0) }
            }
        )
    }

    private func runByTestRun(
        testRunId: String,
        fullHandle: String,
        serverURL: URL,
        pageSize: Int,
        startPage: Int,
        json: Bool
    ) async throws {
        let initialPage = try await listTestCaseRunsByTestRunService.listTestCaseRunsByTestRun(
            fullHandle: fullHandle,
            serverURL: serverURL,
            testRunId: testRunId,
            page: startPage + 1,
            pageSize: pageSize
        )

        let initialRuns = initialPage.test_case_runs

        if json {
            try Noora.current.json(initialRuns)
            return
        }

        if initialRuns.isEmpty {
            Noora.current.passthrough("No test case runs found for test run \(testRunId).")
            return
        }

        let totalPages = initialPage.pagination_metadata.total_pages ?? 1

        let initialRows = initialRuns.map { formatTestRunRow($0) }

        try await Noora.current.paginatedTable(
            headers: ["ID", "Name", "Module", "Status", "Duration", "CI", "Flaky"],
            pageSize: pageSize,
            totalPages: totalPages,
            startPage: startPage,
            loadPage: { [self] pageIndex in
                if pageIndex == startPage {
                    return initialRows
                }

                let runsPage = try await listTestCaseRunsByTestRunService.listTestCaseRunsByTestRun(
                    fullHandle: fullHandle,
                    serverURL: serverURL,
                    testRunId: testRunId,
                    page: pageIndex + 1,
                    pageSize: pageSize
                )

                return runsPage.test_case_runs.map { formatTestRunRow($0) }
            }
        )
    }

    private func formatRunRow(_ run: Operations.listTestCaseRuns.Output.Ok.Body.jsonPayload
        .test_case_runsPayloadPayload) -> [String]
    {
        [
            run.id,
            run.status.rawValue,
            Formatters.formatDuration(run.duration),
            run.is_ci ? "Yes" : "No",
            run.is_flaky ? "Yes" : "No",
            run.git_branch ?? "-",
            run.git_commit_sha.map { String($0.prefix(7)) } ?? "-",
            run.ran_at.map { Formatters.formatDate($0) } ?? "-",
        ]
    }

    private func formatTestRunRow(_ run: Operations.listTestCaseRunsByTestRun.Output.Ok.Body.jsonPayload
        .test_case_runsPayloadPayload) -> [String]
    {
        let name = [run.module_name, run.suite_name, run.name]
            .compactMap { $0 }
            .joined(separator: "/")
        return [
            run.id,
            name,
            run.module_name,
            run.status.rawValue,
            Formatters.formatDuration(run.duration),
            run.is_ci ? "Yes" : "No",
            run.is_flaky ? "Yes" : "No",
        ]
    }
}
