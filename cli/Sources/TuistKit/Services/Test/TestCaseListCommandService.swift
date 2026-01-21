import Foundation
import Noora
import Path
import TuistLoader
import TuistServer
import TuistSupport

protocol TestCaseListCommandServicing {
    func run(
        project: String?,
        path: String?,
        quarantined: Bool,
        flaky: Bool,
        identifiersOnly: Bool,
        page: Int?,
        pageSize: Int,
        json: Bool
    ) async throws
}

enum TestCaseListCommandServiceError: Equatable, LocalizedError {
    case missingFullHandle

    var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            return "We couldn't list test cases because the full handle is missing. You can pass either its value or a path to a Tuist project."
        }
    }
}

struct TestCaseListCommandService: TestCaseListCommandServicing {
    private let listTestCasesService: ListTestCasesServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        listTestCasesService: ListTestCasesServicing = ListTestCasesService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.listTestCasesService = listTestCasesService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(
        project: String?,
        path: String?,
        quarantined: Bool,
        flaky: Bool,
        identifiersOnly: Bool,
        page: Int?,
        pageSize: Int,
        json: Bool
    ) async throws {
        let directoryPath: AbsolutePath = try await Environment.current.pathRelativeToWorkingDirectory(path)

        let config = try await configLoader.loadConfig(path: directoryPath)
        guard let resolvedFullHandle = project ?? config.fullHandle else {
            throw TestCaseListCommandServiceError.missingFullHandle
        }

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        let startPage = (page ?? 1) - 1 // Convert to 0-indexed for Noora

        let initialTestCasesPage = try await listTestCasesService.listTestCases(
            fullHandle: resolvedFullHandle,
            serverURL: serverURL,
            flaky: flaky ? true : nil,
            quarantined: quarantined ? true : nil,
            page: startPage + 1, // API uses 1-indexed pages
            pageSize: pageSize
        )

        let initialTestCases = initialTestCasesPage.test_cases

        if identifiersOnly {
            let identifiers = initialTestCases.map { testCase in
                if let suiteName = testCase.suite?.name {
                    return "\(testCase.module.name)/\(suiteName)/\(testCase.name)"
                } else {
                    return "\(testCase.module.name)/\(testCase.name)"
                }
            }.joined(separator: ",")
            Logger.current.info("\(identifiers)")
            return
        }

        if json {
            try Noora.current.json(initialTestCases)
            return
        }

        if initialTestCases.isEmpty {
            var filters: [String] = []
            if quarantined { filters.append("quarantined") }
            if flaky { filters.append("flaky") }
            let filterDescription = filters.isEmpty ? "" : " with filters: \(filters.joined(separator: ", "))"
            if let page {
                Noora.current.passthrough("No test cases found on page \(page) for project \(resolvedFullHandle)\(filterDescription).")
            } else {
                Noora.current.passthrough("No test cases found for project \(resolvedFullHandle)\(filterDescription).")
            }
            return
        }

        let totalPages = initialTestCasesPage.pagination_metadata.total_pages ?? 1

        let initialRows = initialTestCases.map { testCase in
            [
                testCase.name,
                testCase.module.name,
                testCase.suite?.name ?? "-",
                testCase.is_flaky ? "Yes" : "No",
                testCase.is_quarantined ? "Yes" : "No",
                formatDuration(testCase.avg_duration),
            ]
        }

        try await Noora.current.paginatedTable(
            headers: ["Name", "Module", "Suite", "Flaky", "Quarantined", "Avg Duration"],
            pageSize: pageSize,
            totalPages: totalPages,
            startPage: startPage,
            loadPage: { [self] pageIndex in
                if pageIndex == startPage {
                    return initialRows
                }

                let testCasesPage = try await listTestCasesService.listTestCases(
                    fullHandle: resolvedFullHandle,
                    serverURL: serverURL,
                    flaky: flaky ? true : nil,
                    quarantined: quarantined ? true : nil,
                    page: pageIndex + 1, // API uses 1-indexed pages
                    pageSize: pageSize
                )

                return testCasesPage.test_cases.map { testCase in
                    [
                        testCase.name,
                        testCase.module.name,
                        testCase.suite?.name ?? "-",
                        testCase.is_flaky ? "Yes" : "No",
                        testCase.is_quarantined ? "Yes" : "No",
                        formatDuration(testCase.avg_duration),
                    ]
                }
            }
        )
    }

    private func formatDuration(_ milliseconds: Int) -> String {
        if milliseconds < 1000 {
            return "\(milliseconds)ms"
        } else {
            let seconds = Double(milliseconds) / 1000.0
            return String(format: "%.2fs", seconds)
        }
    }
}
