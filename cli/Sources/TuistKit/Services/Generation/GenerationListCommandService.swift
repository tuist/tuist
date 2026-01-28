import Foundation
import Noora
import OpenAPIURLSession
import Path
import TuistLoader
import TuistServer
import TuistSupport

protocol GenerationListCommandServicing {
    func run(
        project: String?,
        path: String?,
        gitBranch: String?,
        json: Bool
    ) async throws
}

enum GenerationListCommandServiceError: Equatable, LocalizedError {
    case missingFullHandle

    var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            return "We couldn't list generations because the full handle is missing. You can pass either its value or a path to a Tuist project."
        }
    }
}

final class GenerationListCommandService: GenerationListCommandServicing {
    private let listGenerationsService: ListGenerationsServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        listGenerationsService: ListGenerationsServicing = ListGenerationsService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.listGenerationsService = listGenerationsService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(
        project: String?,
        path: String?,
        gitBranch: String?,
        json: Bool
    ) async throws {
        let directoryPath: AbsolutePath = try await Environment.current.pathRelativeToWorkingDirectory(path)

        let config = try await configLoader.loadConfig(path: directoryPath)
        guard let resolvedFullHandle = project != nil ? project! : config.fullHandle else {
            throw GenerationListCommandServiceError.missingFullHandle
        }

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        let response = try await listGenerationsService.listGenerations(
            fullHandle: resolvedFullHandle,
            serverURL: serverURL,
            gitBranch: gitBranch,
            gitCommitSha: nil,
            gitRef: nil,
            page: nil,
            pageSize: 50
        )

        if json {
            try Noora.current.json(response)
            return
        }

        if response.generations.isEmpty {
            let branchFilter = gitBranch.map { " for branch '\($0)'" } ?? ""
            Noora.current.passthrough("No generations found for project \(resolvedFullHandle)\(branchFilter).")
            return
        }

        try Noora.current.paginatedTable(TableData(columns: [
            TableColumn(title: "ID", width: .auto),
            TableColumn(title: "Status", width: .auto),
            TableColumn(title: "Duration", width: .auto),
            TableColumn(title: "CI", width: .auto),
            TableColumn(title: "Branch", width: .auto),
            TableColumn(title: "Date", width: .auto),
            TableColumn(title: "URL", width: .auto),
        ], rows: response.generations.map { generation in
            return [
                "\(generation.id)",
                "\(generation.status)",
                "\(Formatters.formatDuration(generation.duration))",
                "\(generation.is_ci ? "Yes" : "No")",
                "\(generation.git_branch ?? "-")",
                "\(Formatters.formatTimestamp(generation.ran_at))",
                "\(.link(title: "Link", href: generation.url))",
            ]
        }), pageSize: 10)
    }
}
