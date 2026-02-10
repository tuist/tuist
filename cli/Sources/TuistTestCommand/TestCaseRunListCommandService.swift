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
    case invalidIdentifier(String)

    var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            return "We couldn't list test case runs because the project is missing. You can pass either its value or a path to a Tuist project."
        case let .invalidIdentifier(identifier):
            return "Invalid test case identifier '\(identifier)'. Expected format: Module/Suite/TestCase or Module/TestCase."
        }
    }
}

struct TestCaseRunListCommandService: TestCaseRunListCommandServicing {
    private let listTestCaseRunsService: ListTestCaseRunsServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        listTestCaseRunsService: ListTestCaseRunsServicing = ListTestCaseRunsService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
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

        let (moduleName, suiteName, testName) = try parseIdentifier(testCaseIdentifier)

        let pageSize = pageSize ?? 10
        let startPage = (page ?? 1) - 1

        let initialPage = try await listTestCaseRunsService.listTestCaseRuns(
            fullHandle: resolvedFullHandle,
            serverURL: serverURL,
            moduleName: moduleName,
            name: testName,
            suiteName: suiteName,
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
                    moduleName: moduleName,
                    name: testName,
                    suiteName: suiteName,
                    flaky: flaky ? true : nil,
                    page: pageIndex + 1,
                    pageSize: pageSize
                )

                return runsPage.test_case_runs.map { formatRunRow($0) }
            }
        )
    }

    private func parseIdentifier(_ identifier: String) throws -> (moduleName: String, suiteName: String?, testName: String) {
        let parts = identifier.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        switch parts.count {
        case 3:
            return (parts[0], parts[1], parts[2])
        case 2:
            return (parts[0], nil, parts[1])
        default:
            throw TestCaseRunListCommandServiceError.invalidIdentifier(identifier)
        }
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
