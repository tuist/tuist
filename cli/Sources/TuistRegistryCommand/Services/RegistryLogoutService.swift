#if os(macOS)
    import FileSystem
    import Foundation
    import Path
    import TuistConfigLoader
    import TuistEnvironment
    import TuistLogging
    import TuistServer
    import TuistSupport

    struct RegistryLogoutService {
        private let serverEnvironmentService: ServerEnvironmentServicing
        private let configLoader: ConfigLoading
        private let swiftPackageManagerController: SwiftPackageManagerControlling
        private let fileSystem: FileSysteming
        private let registryURLService: RegistryURLServicing

        init(
            serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
            configLoader: ConfigLoading = ConfigLoader(),
            swiftPackageManagerController: SwiftPackageManagerControlling =
                SwiftPackageManagerController(),
            fileSystem: FileSysteming = FileSystem(),
            registryURLService: RegistryURLServicing = RegistryURLService()
        ) {
            self.serverEnvironmentService = serverEnvironmentService
            self.configLoader = configLoader
            self.swiftPackageManagerController = swiftPackageManagerController
            self.fileSystem = fileSystem
            self.registryURLService = registryURLService
        }

        func run(
            path: String?
        ) async throws {
            let path = try await Environment.current.pathRelativeToWorkingDirectory(path)
            let config = try await configLoader.loadConfig(path: path)

            Logger.current.info("Logging out of the registry...")
            let serverURL = try serverEnvironmentService.url(configServerURL: config.url)
            let registryURL =
                try await registryURLService.registryConfiguration(serverURL: serverURL)?.url ?? serverURL

            try await swiftPackageManagerController.packageRegistryLogout(
                registryURL: registryURL
            )

            Logger.current.info("Successfully logged out of the registry.")
        }
    }
#endif
