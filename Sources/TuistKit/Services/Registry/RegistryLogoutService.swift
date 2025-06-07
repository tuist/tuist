import FileSystem
import Foundation
import Path
import TuistLoader
import TuistServer
import TuistSupport

final class RegistryLogoutService {
    private let serverURLService: ServerURLServicing
    private let configLoader: ConfigLoading
    private let swiftPackageManagerController: SwiftPackageManagerControlling
    private let fileSystem: FileSysteming

    init(
        serverURLService: ServerURLServicing = ServerURLService(),
        configLoader: ConfigLoading = ConfigLoader(),
        swiftPackageManagerController: SwiftPackageManagerControlling =
            SwiftPackageManagerController(),
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.serverURLService = serverURLService
        self.configLoader = configLoader
        self.swiftPackageManagerController = swiftPackageManagerController
        self.fileSystem = fileSystem
    }

    func run(
        path: String?
    ) async throws {
        let path = try await Environment.current.pathRelativeToWorkingDirectory(path)
        let config = try await configLoader.loadConfig(path: path)

        Logger.current.info("Logging out of the registry...")
        let serverURL = try serverURLService.url(configServerURL: config.url)

        try await swiftPackageManagerController.packageRegistryLogout(
            registryURL: serverURL
        )

        Logger.current.info("Successfully logged out of the registry.")
    }
}
