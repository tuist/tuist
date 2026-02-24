import FileSystem
import Foundation
import Noora
import Path
import TuistAlert
import TuistConfigLoader
import TuistConstants
import TuistEnvironment
import TuistLogging
import TuistServer

#if os(macOS)
    import TuistLoader
    import TuistSupport
#endif

enum RegistryCommandSetupServiceError: Equatable, LocalizedError {
    case noProjectFound(AbsolutePath)

    var type: ErrorType {
        switch self {
        case .noProjectFound: .abort
        }
    }

    var errorDescription: String? {
        switch self {
        case let .noProjectFound(path):
            return
                "We couldn't find a Package.swift (including Tuist/Package.swift), .xcworkspace, or .xcodeproj at \(path.pathString). The registry setup doesn't use Tuist.swift, so run it from a directory containing one of those files or pass --path to one."
        }
    }
}

struct RegistrySetupCommandService {
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading
    private let fileSystem: FileSysteming

    #if os(macOS)
        private let manifestFilesLocator: ManifestFilesLocating
        private let defaultsController: DefaultsControlling
    #endif

    #if os(macOS)
        init(
            serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
            configLoader: ConfigLoading = ConfigLoader(),
            fileSystem: FileSysteming = FileSystem(),
            manifestFilesLocator: ManifestFilesLocating = ManifestFilesLocator(),
            defaultsController: DefaultsControlling = DefaultsController()
        ) {
            self.serverEnvironmentService = serverEnvironmentService
            self.configLoader = configLoader
            self.fileSystem = fileSystem
            self.manifestFilesLocator = manifestFilesLocator
            self.defaultsController = defaultsController
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
        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        let swiftPackageManagerPath: AbsolutePath

        #if os(macOS)
            if let directoryWithPackageManifest = try await manifestFilesLocator.locatePackageManifest(
                at: path
            )?.parentDirectory {
                swiftPackageManagerPath = directoryWithPackageManifest.appending(component: ".swiftpm")
            } else if let workspacePath = try await fileSystem.glob(
                directory: path, include: ["*.xcworkspace"]
            ).collect().first {
                try await defaultsController.setPackageDendencySCMToRegistryTransformation(
                    .useRegistryIdentityAndSources
                )
                swiftPackageManagerPath = workspacePath.appending(components: "xcshareddata", "swiftpm")
            } else if let projectPath = try await fileSystem.glob(
                directory: path, include: ["*.xcodeproj"]
            ).collect().first {
                try await defaultsController.setPackageDendencySCMToRegistryTransformation(
                    .useRegistryIdentityAndSources
                )
                swiftPackageManagerPath = projectPath.appending(
                    components: "project.xcworkspace", "xcshareddata", "swiftpm"
                )
            } else {
                throw RegistryCommandSetupServiceError.noProjectFound(path)
            }
        #else
            if try await fileSystem.exists(path.appending(components: "Tuist", "Package.swift")) {
                swiftPackageManagerPath = path.appending(components: "Tuist", ".swiftpm")
            } else if try await fileSystem.exists(path.appending(component: "Package.swift")) {
                swiftPackageManagerPath = path.appending(component: ".swiftpm")
            } else {
                throw RegistryCommandSetupServiceError.noProjectFound(path)
            }
        #endif

        let configurationJSONPath = swiftPackageManagerPath.appending(
            components: "configuration", "registries.json"
        )
        if try await !fileSystem.exists(configurationJSONPath.parentDirectory) {
            try await fileSystem.makeDirectory(at: configurationJSONPath.parentDirectory)
        }
        if try await fileSystem.exists(configurationJSONPath) {
            try await fileSystem.remove(configurationJSONPath)
        }
        try await fileSystem.writeText(
            Self.registryConfigurationJSON(serverURL: serverURL),
            at: configurationJSONPath
        )

        AlertController.current.success(
            .alert(
                "Generated the registry configuration file at \(.accent(configurationJSONPath.relative(to: path).pathString))",
                takeaways: [
                    "Commit the generated configuration file to share the configuration with the rest of your team",
                    "For more information about the registry head to our \(.link(title: "docs", href: "https://docs.tuist.dev/en/guides/features/registry"))",
                ]
            )
        )
    }

    static func registryConfigurationJSON(serverURL: URL) -> String {
        let urlString = serverURL.absoluteString
        let trimmedURLString = urlString.hasSuffix("/") ? String(urlString.dropLast()) : urlString
        return """
        {
          "security": {
            "default": {
              "signing": {
                "onUnsigned": "silentAllow"
              }
            }
          },
          "authentication": {
            "\(serverURL.host() ?? Constants.URLs.production.host()!)": {
              "loginAPIPath": "/api/registry/swift/login",
              "type": "token"
            }
          },
          "registries": {
            "[default]": {
              "supportsAvailability": false,
              "url": "\(trimmedURLString)/api/registry/swift"
            }
          },
          "version": 1
        }

        """
    }
}
