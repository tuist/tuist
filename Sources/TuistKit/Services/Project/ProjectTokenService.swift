import Foundation
import Path
import TuistLoader
import TuistServer
import TuistSupport

protocol ProjectTokenServicing {
    func run(
        fullHandle: String,
        directory: String?
    ) async throws
}

final class ProjectTokenService: ProjectTokenServicing {
    private let getProjectService: GetProjectServicing
    private let credentialsStore: ServerCredentialsStoring
    private let serverURLService: ServerURLServicing
    private let configLoader: ConfigLoading

    init(
        getProjectService: GetProjectServicing = GetProjectService(),
        credentialsStore: ServerCredentialsStoring = ServerCredentialsStore(),
        serverURLService: ServerURLServicing = ServerURLService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.getProjectService = getProjectService
        self.credentialsStore = credentialsStore
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
        let config = try configLoader.loadConfig(path: directoryPath)
        let serverURL = try serverURLService.url(configServerURL: config.url)

        let project = try await getProjectService.getProject(
            fullHandle: fullHandle,
            serverURL: serverURL
        )

        logger.info(.init(stringLiteral: project.token))
    }
}
