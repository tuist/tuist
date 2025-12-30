import Foundation
import Path
import TuistCore
import TuistLoader
import TuistServer
import TuistSupport

protocol WhoamiServicing: AnyObject {
    func run(
        directory: String?
    ) async throws
}

final class WhoamiService: WhoamiServicing {
    private let serverSessionController: ServerSessionControlling
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    // MARK: - Init

    init(
        serverSessionController: ServerSessionControlling = ServerSessionController(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.serverSessionController = serverSessionController
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(
        directory: String?
    ) async throws {
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
        let whoami = try await serverSessionController.authenticatedHandle(serverURL: serverURL)
        Logger.current.notice("\(whoami)")
    }
}
