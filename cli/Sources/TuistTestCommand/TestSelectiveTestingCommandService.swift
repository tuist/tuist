import Foundation
import Noora
import Path
import TuistConfigLoader
import TuistEnvironment
import TuistNooraExtension
import TuistServer

enum TestSelectiveTestingCommandServiceError: Equatable, LocalizedError {
    case missingFullHandle

    var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            return "We couldn't read the test run's selective testing because the project is missing. You can pass either its value or a path to a Tuist project."
        }
    }
}

private func resolveProject(
    project: String?,
    path: String?,
    configLoader: ConfigLoading,
    serverEnvironmentService: ServerEnvironmentServicing
) async throws -> (fullHandle: String, serverURL: URL) {
    let directoryPath: AbsolutePath = try await Environment.current.pathRelativeToWorkingDirectory(path)
    let config = try await configLoader.loadConfig(path: directoryPath)
    guard let fullHandle = project ?? config.fullHandle else {
        throw TestSelectiveTestingCommandServiceError.missingFullHandle
    }
    return (fullHandle, try serverEnvironmentService.url(configServerURL: config.url))
}

struct TestSelectiveTestingListCommandService {
    private let selectiveTestingService: SelectiveTestingServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        selectiveTestingService: SelectiveTestingServicing = SelectiveTestingService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.selectiveTestingService = selectiveTestingService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(
        project: String?,
        testRunId: String,
        path: String?,
        decision: String?,
        reason: String?,
        search: String?,
        page: Int?,
        pageSize: Int?,
        json: Bool
    ) async throws {
        let (fullHandle, serverURL) = try await resolveProject(
            project: project,
            path: path,
            configLoader: configLoader,
            serverEnvironmentService: serverEnvironmentService
        )
        let startPage = (page ?? 1) - 1
        let pageSize = pageSize ?? 20

        let fetch = { (pageIndex: Int) in
            try await selectiveTestingService.listTests(
                fullHandle: fullHandle,
                serverURL: serverURL,
                testRunId: testRunId,
                decision: decision,
                reason: reason,
                search: search,
                page: pageIndex + 1,
                pageSize: pageSize
            )
        }

        let initialPage = try await fetch(startPage)

        if json {
            try Noora.current.json(initialPage)
            return
        }

        if initialPage.tests.isEmpty {
            Noora.current.passthrough("No tests found for test run \(testRunId)'s coverage-based selection.")
            return
        }

        try await Noora.current.paginatedTable(
            headers: ["Test", "Decision", "Reason", "Matched Path", "Outcome"],
            pageSize: pageSize,
            totalPages: initialPage.pagination_metadata.total_pages ?? 1,
            startPage: startPage,
            loadPage: { pageIndex in
                let page = pageIndex == startPage ? initialPage : try await fetch(pageIndex)
                return page.tests.map { test in
                    [
                        "\(test.module_name)/\(test.suite_name)/\(test.name)",
                        test.decision.rawValue,
                        test.reason,
                        test.matched_path ?? "-",
                        test.outcome ?? "-",
                    ]
                }
            }
        )
    }
}

struct TestSelectiveTestingFilesCommandService {
    private let selectiveTestingService: SelectiveTestingServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        selectiveTestingService: SelectiveTestingServicing = SelectiveTestingService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.selectiveTestingService = selectiveTestingService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(
        project: String?,
        testRunId: String,
        path: String?,
        search: String?,
        page: Int?,
        pageSize: Int?,
        json: Bool
    ) async throws {
        let (fullHandle, serverURL) = try await resolveProject(
            project: project,
            path: path,
            configLoader: configLoader,
            serverEnvironmentService: serverEnvironmentService
        )
        let startPage = (page ?? 1) - 1
        let pageSize = pageSize ?? 20

        let fetch = { (pageIndex: Int) in
            try await selectiveTestingService.listChangedFiles(
                fullHandle: fullHandle,
                serverURL: serverURL,
                testRunId: testRunId,
                search: search,
                page: pageIndex + 1,
                pageSize: pageSize
            )
        }

        let initialPage = try await fetch(startPage)

        if json {
            try Noora.current.json(initialPage)
            return
        }

        if initialPage.changed_files.isEmpty {
            Noora.current.passthrough(
                "No changed files found for test run \(testRunId). The run had no coverage-based selection baseline, ran from a dirty checkout, or its diff expired."
            )
            return
        }

        try await Noora.current.paginatedTable(
            headers: ["Path", "Status", "Tracked", "Selected Tests"],
            pageSize: pageSize,
            totalPages: initialPage.pagination_metadata.total_pages ?? 1,
            startPage: startPage,
            loadPage: { pageIndex in
                let page = pageIndex == startPage ? initialPage : try await fetch(pageIndex)
                return page.changed_files.map { file in
                    [file.path, file.status, file.tracked ? "Yes" : "No", "\(file.selected_tests_count)"]
                }
            }
        )
    }
}
