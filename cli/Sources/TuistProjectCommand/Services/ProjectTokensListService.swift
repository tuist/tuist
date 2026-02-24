import Foundation
import Noora
import Path
import TuistAlert
import TuistConfigLoader
import TuistEnvironment
import TuistLogging
import TuistServer

protocol ProjectTokensListServicing {
    func run(
        fullHandle: String,
        directory: String?
    ) async throws
}

struct ProjectTokensListService: ProjectTokensListServicing {
    private let listProjectTokensService: ListProjectTokensServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        listProjectTokensService: ListProjectTokensServicing = ListProjectTokensService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.listProjectTokensService = listProjectTokensService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(
        fullHandle: String,
        directory: String?
    ) async throws {
        AlertController.current.warning(.alert(
            "Project tokens are deprecated in favor of account tokens",
            takeaway: "Learn more: https://docs.tuist.dev/en/guides/server/authentication#account-tokens"
        ))

        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(directory)
        let config = try await configLoader.loadConfig(path: directoryPath)
        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        let tokens = try await listProjectTokensService.listProjectTokens(
            fullHandle: fullHandle,
            serverURL: serverURL
        )

        if tokens.isEmpty {
            Logger.current
                .notice(
                    "No project tokens found. Create one by running `tuist project tokens create \(fullHandle)."
                )
        } else {
            try Noora.current.paginatedTable(
                TableData(
                    columns: [
                        TableColumn(title: "ID", width: .auto),
                        TableColumn(title: "Created at", width: .auto),
                    ],
                    rows: tokens.map { token in
                        [
                            "\(token.id)",
                            "\(token.insertedAt)",
                        ]
                    }
                ),
                pageSize: 10
            )
        }
    }
}
