import FileSystem
import Foundation
import Path
import ServiceContextModule
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
        swiftPackageManagerController: SwiftPackageManagerControlling = SwiftPackageManagerController(),
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
        let path = try await self.path(path)
        let config = try await configLoader.loadConfig(path: path)

        ServiceContext.current?.logger?.info("Logging out of the registry...")
        let serverURL = try serverURLService.url(configServerURL: config.url)

        try await swiftPackageManagerController.packageRegistryLogout(
            registryURL: serverURL
        )

        ServiceContext.current?.logger?.info("Successfully logged out of the registry.")
    }

    private func path(_ path: String?) async throws -> AbsolutePath {
        if let path {
            return try await AbsolutePath(validating: path, relativeTo: fileSystem.currentWorkingDirectory())
        } else {
            return try await fileSystem.currentWorkingDirectory()
        }
    }
}
