import Foundation
import Path
import ServiceContextModule
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
    private let serverURLService: ServerURLServicing
    private let configLoader: ConfigLoading

    init(
        listProjectTokensService: ListProjectTokensServicing = ListProjectTokensService(),
        serverURLService: ServerURLServicing = ServerURLService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.listProjectTokensService = listProjectTokensService
        self.serverURLService = serverURLService
        self.configLoader = configLoader
    }

    func run(
        fullHandle: String,
        directory: String?
    ) async throws {
        let directoryPath: AbsolutePath
        if let directory {
            directoryPath = try AbsolutePath(validating: directory, relativeTo: FileHandler.shared.currentPath)
        } else {
            directoryPath = FileHandler.shared.currentPath
        }
        let config = try await configLoader.loadConfig(path: directoryPath)
        let serverURL = try serverURLService.url(configServerURL: config.url)

        let tokens = try await listProjectTokensService.listProjectTokens(
            fullHandle: fullHandle,
            serverURL: serverURL
        )

        if tokens.isEmpty {
            ServiceContext.current?.logger?
                .notice("No project tokens found. Create one by running `tuist project tokens create \(fullHandle).")
        } else {
            let textTable = TextTable<ServerProjectToken> { [
                TextTable.Column(title: "ID", value: $0.id),
                TextTable.Column(title: "Created at", value: $0.insertedAt),
            ] }
            ServiceContext.current?.logger?.notice("\(textTable.render(tokens))")
        }
    }
}
