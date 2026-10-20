import Foundation
import TuistAlert
import TuistConfigLoader
import TuistEnvironment
import TuistServer

struct ProjectRepositoryDisconnectService {
    private let configLoader: ConfigLoading
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let disconnectProjectRepositoryService: DisconnectProjectRepositoryServicing

    init(
        configLoader: ConfigLoading = ConfigLoader(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        disconnectProjectRepositoryService: DisconnectProjectRepositoryServicing = DisconnectProjectRepositoryService()
    ) {
        self.configLoader = configLoader
        self.serverEnvironmentService = serverEnvironmentService
        self.disconnectProjectRepositoryService = disconnectProjectRepositoryService
    }

    func run(fullHandle: String?, path: String?) async throws {
        let path = try await Environment.current.pathRelativeToWorkingDirectory(path)
        let config = try await configLoader.loadConfig(path: path)
        guard let fullHandle = fullHandle ?? config.fullHandle else {
            throw ProjectRepositoryServiceError.missingFullHandle
        }
        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        try await disconnectProjectRepositoryService.disconnectProjectRepository(
            fullHandle: fullHandle,
            serverURL: serverURL
        )

        AlertController.current.success(.alert("The project \(fullHandle) is no longer linked to a repository"))
    }
}
