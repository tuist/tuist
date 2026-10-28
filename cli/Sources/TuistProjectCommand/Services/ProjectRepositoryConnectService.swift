import Foundation
import TuistAlert
import TuistConfigLoader
import TuistEnvironment
import TuistLogging
import TuistServer

enum ProjectRepositoryServiceError: Equatable, FatalError {
    case missingFullHandle

    var type: ErrorType {
        switch self {
        case .missingFullHandle: .abort
        }
    }

    var description: String {
        switch self {
        case .missingFullHandle:
            return
                "The project's full handle is missing. Pass it with --project or run the command from a Tuist project that sets fullHandle."
        }
    }
}

struct ProjectRepositoryConnectService {
    private let configLoader: ConfigLoading
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let connectProjectRepositoryService: ConnectProjectRepositoryServicing

    init(
        configLoader: ConfigLoading = ConfigLoader(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        connectProjectRepositoryService: ConnectProjectRepositoryServicing = ConnectProjectRepositoryService()
    ) {
        self.configLoader = configLoader
        self.serverEnvironmentService = serverEnvironmentService
        self.connectProjectRepositoryService = connectProjectRepositoryService
    }

    func run(repository: String, fullHandle: String?, path: String?) async throws {
        let path = try await Environment.current.pathRelativeToWorkingDirectory(path)
        let config = try await configLoader.loadConfig(path: path)
        guard let fullHandle = fullHandle ?? config.fullHandle else {
            throw ProjectRepositoryServiceError.missingFullHandle
        }
        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        let repositoryFullHandle = try await connectProjectRepositoryService.connectProjectRepository(
            fullHandle: fullHandle,
            repositoryFullHandle: repository,
            serverURL: serverURL
        )

        AlertController.current.success(
            .alert("The project \(fullHandle) is linked to \(repositoryFullHandle)")
        )
    }
}
