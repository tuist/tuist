import Foundation
import Path
import ServiceContextModule
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
    private let serverURLService: ServerURLServicing
    private let configLoader: ConfigLoading

    // MARK: - Init

    init(
        serverSessionController: ServerSessionControlling = ServerSessionController(),
        serverURLService: ServerURLServicing = ServerURLService(),
        configLoader: ConfigLoading = ConfigLoader(warningController: WarningController.shared)
    ) {
        self.serverSessionController = serverSessionController
        self.serverURLService = serverURLService
        self.configLoader = configLoader
    }

    func run(
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
        if let whoami = try await serverSessionController.whoami(serverURL: serverURL) {
            ServiceContext.current?.logger?.notice("\(whoami)")
        } else {
            ServiceContext.current?.logger?.notice("You are not logged in. Run 'tuist auth login'.")
        }
    }
}
