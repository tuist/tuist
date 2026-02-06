import Foundation
import Noora
import Path
import TuistConfigLoader
import TuistEnvironment
import TuistLoader
import TuistServer
import TuistSupport

protocol GenerationListCommandServicing {
    func run(
        projectFullHandle: String?,
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

struct GenerationListCommandService: GenerationListCommandServicing {
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
        projectFullHandle: String?,
        path: String?,
        gitBranch: String?,
        json: Bool
    ) async throws {
        let directoryPath: AbsolutePath = try await Environment.current.pathRelativeToWorkingDirectory(path)

        let config = try await configLoader.loadConfig(path: directoryPath)
        guard let resolvedFullHandle = projectFullHandle ?? config.fullHandle else {
            throw GenerationListCommandServiceError.missingFullHandle
        }

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        let pageSize = 10
        let startPage = 0

        let response = try await listGenerationsService.listGenerations(
            fullHandle: resolvedFullHandle,
            serverURL: serverURL,
            gitBranch: gitBranch,
            gitCommitSha: nil,
            gitRef: nil,
            page: startPage + 1,
            pageSize: pageSize
        )

        if json {
            try Noora.current.json(response)
            return
        }

        let generations = response.generations

        if generations.isEmpty {
            let branchFilter = gitBranch.map { " for branch '\($0)'" } ?? ""
            Noora.current.passthrough("No generations found for project \(resolvedFullHandle)\(branchFilter).")
            return
        }

        let totalPages = response.pagination_metadata.total_pages ?? 1

        let initialRows = generations.map { generation in
            [
                "\(generation.id)",
                "\(generation.status)",
                "\(Formatters.formatDuration(generation.duration))",
                generation.is_ci ? "Yes" : "No",
                generation.git_branch ?? "-",
                Formatters.formatTimestamp(generation.ran_at),
                generation.url,
            ]
        }

        try await Noora.current.paginatedTable(
            headers: ["ID", "Status", "Duration", "CI", "Branch", "Date", "URL"],
            pageSize: pageSize,
            totalPages: totalPages,
            startPage: startPage,
            loadPage: { [self] pageIndex in
                if pageIndex == startPage {
                    return initialRows
                }

                let pageResponse = try await listGenerationsService.listGenerations(
                    fullHandle: resolvedFullHandle,
                    serverURL: serverURL,
                    gitBranch: gitBranch,
                    gitCommitSha: nil,
                    gitRef: nil,
                    page: pageIndex + 1,
                    pageSize: pageSize
                )

                return pageResponse.generations.map { generation in
                    [
                        "\(generation.id)",
                        "\(generation.status)",
                        "\(Formatters.formatDuration(generation.duration))",
                        generation.is_ci ? "Yes" : "No",
                        generation.git_branch ?? "-",
                        Formatters.formatTimestamp(generation.ran_at),
                        generation.url,
                    ]
                }
            }
        )
    }
}
