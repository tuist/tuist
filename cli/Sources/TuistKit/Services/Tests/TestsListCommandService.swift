import Foundation
import Noora
import Path
import TuistLoader
import TuistServer
import TuistSupport

protocol TestsListCommandServicing {
    func run(
        project: String?,
        path: String?,
        status: String?,
        scheme: String?,
        gitBranch: String?,
        gitCommitSHA: String?,
        gitRef: String?,
        json: Bool
    ) async throws
}

enum TestsListCommandServiceError: Equatable, LocalizedError {
    case missingFullHandle

    var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            return "We couldn't list tests because the full handle is missing. You can pass either its value or a path to a Tuist project."
        }
    }
}

final class TestsListCommandService: TestsListCommandServicing {
    private let listTestsService: ListTestsServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        listTestsService: ListTestsServicing = ListTestsService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.listTestsService = listTestsService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(
        project: String?,
        path: String?,
        status: String?,
        scheme: String?,
        gitBranch: String?,
        gitCommitSHA: String?,
        gitRef: String?,
        json: Bool
    ) async throws {
        let directoryPath: AbsolutePath = try await Environment.current.pathRelativeToWorkingDirectory(path)

        let config = try await configLoader.loadConfig(path: directoryPath)
        guard let resolvedFullHandle = project != nil ? project! : config.fullHandle else {
            throw TestsListCommandServiceError.missingFullHandle
        }

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        let response = try await listTestsService.listTests(
            fullHandle: resolvedFullHandle,
            status: status,
            scheme: scheme,
            gitBranch: gitBranch,
            gitCommitSHA: gitCommitSHA,
            gitRef: gitRef,
            page: nil,
            pageSize: 50,
            serverURL: serverURL
        )

        if json {
            try Noora.current.json(response)
            return
        }

        if response.tests.isEmpty {
            Noora.current.passthrough("No tests found for project \(resolvedFullHandle).")
            return
        }

        try Noora.current.paginatedTable(TableData(columns: [
            TableColumn(title: "ID", width: .auto),
            TableColumn(title: "Duration (ms)", width: .auto),
            TableColumn(title: "Status", width: .auto),
            TableColumn(title: "Ran at", width: .auto),
            TableColumn(title: "URL", width: .auto),
        ], rows: response.tests.map { test in
            return [
                test.id,
                "\(test.duration)",
                test.status,
                "\(Formatters.formatDate(Date(timeIntervalSince1970: TimeInterval(test.ran_at))))",
                "\(.link(title: "Link", href: test.url))",
            ]
        }), pageSize: 10)
    }
}
