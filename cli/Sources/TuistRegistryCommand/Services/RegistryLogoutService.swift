import FileSystem
import Foundation
import Path
import TuistConfigLoader
import TuistEnvironment
import TuistLogging
import TuistServer

#if os(macOS)
    import TuistSupport
#endif

enum RegistryLogoutServiceError: LocalizedError {
    case logoutCommandFailed(Int32)

    var errorDescription: String? {
        switch self {
        case let .logoutCommandFailed(exitCode):
            return "The 'swift package-registry logout' command failed with exit code \(exitCode)."
        }
    }
}

final class RegistryLogoutService {
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading
    private let fileSystem: FileSysteming

    #if os(macOS)
        private let swiftPackageManagerController: SwiftPackageManagerControlling

        init(
            serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
            configLoader: ConfigLoading = ConfigLoader(),
            swiftPackageManagerController: SwiftPackageManagerControlling =
                SwiftPackageManagerController(),
            fileSystem: FileSysteming = FileSystem()
        ) {
            self.serverEnvironmentService = serverEnvironmentService
            self.configLoader = configLoader
            self.swiftPackageManagerController = swiftPackageManagerController
            self.fileSystem = fileSystem
        }
    #else
        init(
            serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
            configLoader: ConfigLoading = ConfigLoader(),
            fileSystem: FileSysteming = FileSystem()
        ) {
            self.serverEnvironmentService = serverEnvironmentService
            self.configLoader = configLoader
            self.fileSystem = fileSystem
        }
    #endif

    func run(
        path: String?
    ) async throws {
        let path = try await Environment.current.pathRelativeToWorkingDirectory(path)
        let config = try await configLoader.loadConfig(path: path)

        Logger.current.info("Logging out of the registry...")
        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        #if os(macOS)
            try await swiftPackageManagerController.packageRegistryLogout(
                registryURL: serverURL
            )
        #else
            let logoutURL = serverURL.appending(path: "logout").absoluteString
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
            process.arguments = ["package-registry", "logout", logoutURL]
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw RegistryLogoutServiceError.logoutCommandFailed(process.terminationStatus)
            }
        #endif

        Logger.current.info("Successfully logged out of the registry.")
    }
}
