import Foundation
import Noora
import Path
import TuistLoader
import TuistServer
import TuistSupport

protocol BuildsListCommandServicing {
    func run(
        project: String?,
        path: String?,
        status: String?,
        category: String?,
        scheme: String?,
        configuration: String?,
        gitBranch: String?,
        gitCommitSHA: String?,
        gitRef: String?,
        page: Int?,
        perPage: Int?,
        json: Bool
    ) async throws
}

enum BuildsListCommandServiceError: Equatable, LocalizedError {
    case missingFullHandle

    var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            return "We couldn't list builds because the full handle is missing. You can pass either its value or a path to a Tuist project."
        }
    }
}

final class BuildsListCommandService: BuildsListCommandServicing {
    private let listBuildsService: ListBuildsServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        listBuildsService: ListBuildsServicing = ListBuildsService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.listBuildsService = listBuildsService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(
        project: String?,
        path: String?,
        status: String?,
        category: String?,
        scheme: String?,
        configuration: String?,
        gitBranch: String?,
        gitCommitSHA: String?,
        gitRef: String?,
        page: Int?,
        perPage: Int?,
        json: Bool
    ) async throws {
        let directoryPath: AbsolutePath = try await Environment.current.pathRelativeToWorkingDirectory(path)

        let config = try await configLoader.loadConfig(path: directoryPath)
        guard let resolvedFullHandle = project != nil ? project! : config.fullHandle else {
            throw BuildsListCommandServiceError.missingFullHandle
        }

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        let response = try await listBuildsService.listBuilds(
            fullHandle: resolvedFullHandle,
            status: status,
            category: category,
            scheme: scheme,
            configuration: configuration,
            gitBranch: gitBranch,
            gitCommitSHA: gitCommitSHA,
            gitRef: gitRef,
            page: page,
            pageSize: perPage,
            serverURL: serverURL
        )

        if json {
            try Noora.current.json(response)
            return
        }

        if response.builds.isEmpty {
            Noora.current.passthrough("No builds found for project \(resolvedFullHandle).")
            return
        }

        try Noora.current.paginatedTable(TableData(columns: [
            TableColumn(title: "ID", width: .auto),
            TableColumn(title: "Duration (ms)", width: .auto),
            TableColumn(title: "Status", width: .auto),
            TableColumn(title: "Ran at", width: .auto),
            TableColumn(title: "URL", width: .auto),
        ], rows: response.builds.map { build in
            return [
                "\(build.id)",
                "\(build.duration)",
                "\(build.status)",
                "\(Formatters.formatDate(Date(timeIntervalSince1970: TimeInterval(build.ran_at))))",
                "\(.link(title: "Link", href: build.url))",
            ]
        }), pageSize: 10)
    }
}
