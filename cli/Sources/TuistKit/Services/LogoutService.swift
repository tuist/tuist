import Foundation
import Path
import TuistCore
import TuistLoader
import TuistServer
import TuistSupport

protocol LogoutServicing: AnyObject {
    /// It removes any session associated to that domain from
    /// the keychain
    func logout(
        directory: String?
    ) async throws
}

final class LogoutService: LogoutServicing {
    private let serverSessionController: ServerSessionControlling
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        serverSessionController: ServerSessionControlling = ServerSessionController(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.serverSessionController = serverSessionController
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func logout(
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
        try await serverSessionController.logout(serverURL: serverURL)
        AlertController.current.success("Successfully logged out")
    }
}
