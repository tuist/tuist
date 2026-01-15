import Foundation
import Noora
import Path
import TuistLoader
import TuistServer
import TuistSupport

protocol TestCasesListCommandServicing {
    func run(
        project: String?,
        path: String?,
        name: String?,
        moduleName: String?,
        suiteName: String?,
        status: String?,
        json: Bool
    ) async throws
}

enum TestCasesListCommandServiceError: Equatable, LocalizedError {
    case missingFullHandle

    var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            return "We couldn't list test cases because the full handle is missing. You can pass either its value or a path to a Tuist project."
        }
    }
}

final class TestCasesListCommandService: TestCasesListCommandServicing {
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
        name: String?,
        moduleName: String?,
        suiteName: String?,
        status: String?,
        json: Bool
    ) async throws {
        let directoryPath: AbsolutePath = try await Environment.current.pathRelativeToWorkingDirectory(path)

        let config = try await configLoader.loadConfig(path: directoryPath)
        guard let resolvedFullHandle = project != nil ? project! : config.fullHandle else {
            throw TestCasesListCommandServiceError.missingFullHandle
        }

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        let response = try await listTestCasesService.listTestCases(
            fullHandle: resolvedFullHandle,
            name: name,
            moduleName: moduleName,
            suiteName: suiteName,
            status: status,
            page: nil,
            pageSize: 50,
            serverURL: serverURL
        )

        if json {
            try Noora.current.json(response)
            return
        }

        if response.test_cases.isEmpty {
            Noora.current.passthrough("No test cases found for project \(resolvedFullHandle).")
            return
        }

        try Noora.current.paginatedTable(TableData(columns: [
            TableColumn(title: "ID", width: .auto),
            TableColumn(title: "Name", width: .auto),
            TableColumn(title: "Status", width: .auto),
            TableColumn(title: "Last ran at", width: .auto),
            TableColumn(title: "URL", width: .auto),
        ], rows: response.test_cases.map { testCase in
            return [
                testCase.id,
                testCase.name,
                testCase.last_status,
                "\(Formatters.formatDate(Date(timeIntervalSince1970: TimeInterval(testCase.last_ran_at))))",
                "\(.link(title: "Link", href: testCase.url))",
            ]
        }), pageSize: 10)
    }
}
