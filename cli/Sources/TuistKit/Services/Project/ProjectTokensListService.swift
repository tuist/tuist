import Foundation
import Path
import TuistLoader
import TuistServer
import TuistSupport

protocol ProjectTokensListServicing {
    func run(
        fullHandle: String,
        directory: String?
    ) async throws
}

final class ProjectTokensListService: ProjectTokensListServicing {
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

        let directoryPath: AbsolutePath
        if let directory {
            directoryPath = try AbsolutePath(
                validating: directory, relativeTo: FileHandler.shared.currentPath
            )
        } else {
            directoryPath = FileHandler.shared.currentPath
        }
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
            let textTable = TextTable<ServerProjectToken> {
                [
                    TextTable.Column(title: "ID", value: $0.id),
                    TextTable.Column(title: "Created at", value: $0.insertedAt),
                ]
            }
            Logger.current.notice("\(textTable.render(tokens))")
        }
    }
}
