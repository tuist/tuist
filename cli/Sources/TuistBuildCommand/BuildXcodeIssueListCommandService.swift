import Foundation
import Noora
import Path
import TuistConfigLoader
import TuistEnvironment
import TuistServer

protocol BuildXcodeIssueListCommandServicing {
    func run(
        fullHandle: String?,
        buildId: String,
        path: String?,
        type: String?,
        target: String?,
        page: Int?,
        pageSize: Int?,
        json: Bool
    ) async throws
}

enum BuildXcodeIssueListCommandServiceError: Equatable, LocalizedError {
    case missingFullHandle

    var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            return "We couldn't list the build issues because the full handle is missing. You can pass either its value or a path to a Tuist project."
        }
    }
}

struct BuildXcodeIssueListCommandService: BuildXcodeIssueListCommandServicing {
    private let listBuildIssuesService: ListBuildIssuesServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        listBuildIssuesService: ListBuildIssuesServicing = ListBuildIssuesService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.listBuildIssuesService = listBuildIssuesService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(
        fullHandle: String?,
        buildId: String,
        path: String?,
        type: String?,
        target: String?,
        page: Int?,
        pageSize: Int?,
        json: Bool
    ) async throws {
        let directoryPath: AbsolutePath = try await Environment.current.pathRelativeToWorkingDirectory(path)

        let config = try await configLoader.loadConfig(path: directoryPath)
        guard let resolvedFullHandle = fullHandle ?? config.fullHandle else {
            throw BuildXcodeIssueListCommandServiceError.missingFullHandle
        }

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        let startPage = (page ?? 1) - 1
        let pageSize = pageSize ?? 10

        let initialPage = try await listBuildIssuesService.listBuildIssues(
            fullHandle: resolvedFullHandle,
            serverURL: serverURL,
            buildId: buildId,
            type: type,
            target: target,
            stepType: nil,
            page: startPage + 1,
            pageSize: pageSize
        )

        let issues = initialPage.issues

        if json {
            try Noora.current.json(issues)
            return
        }

        if issues.isEmpty {
            Noora.current.passthrough("No issues found for build \(buildId).")
            return
        }

        let totalPages = initialPage.pagination_metadata.total_pages ?? 1

        let initialRows = issues.map { issue in
            [
                issue._type.rawValue,
                issue.message ?? issue.title,
                issue.target,
                issue.path ?? "-",
            ]
        }

        try await Noora.current.paginatedTable(
            headers: ["Type", "Message", "Target", "File"],
            pageSize: pageSize,
            totalPages: totalPages,
            startPage: startPage,
            loadPage: { [self] pageIndex in
                if pageIndex == startPage {
                    return initialRows
                }
                let issuePage = try await listBuildIssuesService.listBuildIssues(
                    fullHandle: resolvedFullHandle,
                    serverURL: serverURL,
                    buildId: buildId,
                    type: type,
                    target: target,
                    stepType: nil,
                    page: pageIndex + 1,
                    pageSize: pageSize
                )
                return issuePage.issues.map { issue in
                    [
                        issue._type.rawValue,
                        issue.message ?? issue.title,
                        issue.target,
                        issue.path ?? "-",
                    ]
                }
            }
        )
    }
}
