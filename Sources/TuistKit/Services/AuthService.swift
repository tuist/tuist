import Foundation
import Mockable
import Path
import TuistCore
import TuistLoader
import TuistServer
import TuistSupport

@Mockable
protocol AuthServicing: AnyObject {
    func authenticate(
        directory: String?
    ) async throws
}

final class AuthService: AuthServicing {
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

    // MARK: - AuthServicing

    func authenticate(
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
        try await serverSessionController.authenticate(serverURL: serverURL)
    }
}
