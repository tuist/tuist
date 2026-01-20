import FileSystem
import Foundation
import Noora
import Path
import TuistLoader
import TuistServer
import TuistSupport

enum RegistryCommandSetupServiceError: Equatable, LocalizedError {
    case noProjectFound(AbsolutePath)

    var type: TuistSupport.ErrorType {
        switch self {
        case .noProjectFound: .abort
        }
    }

    var errorDescription: String? {
        switch self {
        case let .noProjectFound(path):
            return
                "We couldn't find an Xcode, SwiftPM, or Tuist project at \(path.pathString). Make sure you're in the right directory."
        }
    }
}

struct RegistrySetupCommandService {
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading
    private let fileSystem: FileSysteming
    private let manifestFilesLocator: ManifestFilesLocating
    private let swiftPackageManagerController: SwiftPackageManagerControlling
    private let createAccountTokenService: CreateAccountTokenServicing
    private let defaultsController: DefaultsControlling

    init(
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader(),
        fileSystem: FileSysteming = FileSystem(),
        manifestFilesLocator: ManifestFilesLocating = ManifestFilesLocator(),
        swiftPackageManagerController: SwiftPackageManagerControlling =
            SwiftPackageManagerController(),
        createAccountTokenService: CreateAccountTokenServicing = CreateAccountTokenService(),
        defaultsController: DefaultsControlling = DefaultsController()
    ) {
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
        self.fileSystem = fileSystem
        self.manifestFilesLocator = manifestFilesLocator
        self.swiftPackageManagerController = swiftPackageManagerController
        self.createAccountTokenService = createAccountTokenService
        self.defaultsController = defaultsController
    }

    func run(
        path: String?
    ) async throws {
        let path = try await Environment.current.pathRelativeToWorkingDirectory(path)
        let config = try await configLoader.loadConfig(path: path)
        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        let swiftPackageManagerPath: AbsolutePath

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
            registryConfigurationJSON(
                serverURL: serverURL
            ),
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

    private func registryConfigurationJSON(
        serverURL: URL
    ) -> String {
        """
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
              "url": "\(serverURL.absoluteString.dropSuffix("/"))/api/registry/swift"
            }
          },
          "version": 1
        }

        """
    }
}
