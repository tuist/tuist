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
    private let serverURLService: ServerURLServicing
    private let configLoader: ConfigLoading

    init(
        serverSessionController: ServerSessionControlling = ServerSessionController(),
        serverURLService: ServerURLServicing = ServerURLService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.serverSessionController = serverSessionController
        self.serverURLService = serverURLService
        self.configLoader = configLoader
    }

    func logout(
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
        try await serverSessionController.logout(serverURL: serverURL)
    }
}
