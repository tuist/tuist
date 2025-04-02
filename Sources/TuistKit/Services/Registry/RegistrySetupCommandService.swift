import FileSystem
import Foundation
import Path
import ServiceContextModule
import TuistLoader
import TuistServer
import TuistSupport

enum RegistryCommandSetupServiceError: Equatable, LocalizedError {
    case missingFullHandle
    case noProjectFound(AbsolutePath)

    var type: TuistSupport.ErrorType {
        switch self {
        case .missingFullHandle, .noProjectFound: .abort
        }
    }

    var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            return "We couldn't set up the registry because the project is missing the 'fullHandle' in the 'Tuist.swift' file."
        case let .noProjectFound(path):
            return "We couldn't find an Xcode, SwiftPM, or Tuist project at \(path.pathString). Make sure you're in the right directory."
        }
    }
}

struct RegistrySetupCommandService {
    private let serverURLService: ServerURLServicing
    private let configLoader: ConfigLoading
    private let fileSystem: FileSysteming
    private let fullHandleService: FullHandleServicing
    private let manifestFilesLocator: ManifestFilesLocating
    private let swiftPackageManagerController: SwiftPackageManagerControlling
    private let createAccountTokenService: CreateAccountTokenServicing
    private let defaultsController: DefaultsControlling

    init(
        serverURLService: ServerURLServicing = ServerURLService(),
        configLoader: ConfigLoading = ConfigLoader(),
        fileSystem: FileSysteming = FileSystem(),
        fullHandleService: FullHandleServicing = FullHandleService(),
        manifestFilesLocator: ManifestFilesLocating = ManifestFilesLocator(),
        swiftPackageManagerController: SwiftPackageManagerControlling = SwiftPackageManagerController(),
        createAccountTokenService: CreateAccountTokenServicing = CreateAccountTokenService(),
        defaultsController: DefaultsControlling = DefaultsController()
    ) {
        self.serverURLService = serverURLService
        self.configLoader = configLoader
        self.fileSystem = fileSystem
        self.fullHandleService = fullHandleService
        self.manifestFilesLocator = manifestFilesLocator
        self.swiftPackageManagerController = swiftPackageManagerController
        self.createAccountTokenService = createAccountTokenService
        self.defaultsController = defaultsController
    }

    func run(
        path: String?
    ) async throws {
        let path = try await self.path(path)
        let config = try await configLoader.loadConfig(path: path)

        guard let fullHandle = config.fullHandle else { throw RegistryCommandSetupServiceError.missingFullHandle }
        let accountHandle = try fullHandleService.parse(fullHandle).accountHandle

        let serverURL = try serverURLService.url(configServerURL: config.url)

        try await ServiceContext.current?.ui?.progressStep(
            message: "Logging into the registry...",
            successMessage: "Logged in to the \(accountHandle) registry",
            errorMessage: nil,
            showSpinner: true
        ) { _ in
            let serverURL = try serverURLService.url(configServerURL: config.url)
            let registryURL = serverURL.appending(path: "api/accounts/\(accountHandle)/registry/swift")

            let token = try await createAccountTokenService.createAccountToken(
                accountHandle: accountHandle,
                scopes: [.accountRegistryRead],
                serverURL: serverURL
            )
            try await swiftPackageManagerController.packageRegistryLogin(
                token: token,
                registryURL: registryURL
            )
        }

        let swiftPackageManagerPath: AbsolutePath

        if let directoryWithPackageManifest = try await manifestFilesLocator.locatePackageManifest(at: path)?.parentDirectory {
            swiftPackageManagerPath = directoryWithPackageManifest.appending(component: ".swiftpm")
        } else if let workspacePath = try await fileSystem.glob(directory: path, include: ["*.xcworkspace"]).collect().first {
            try await defaultsController.setPackageDendencySCMToRegistryTransformation(.useRegistryIdentityAndSources)
            swiftPackageManagerPath = workspacePath.appending(components: "xcshareddata", "swiftpm")
        } else if let projectPath = try await fileSystem.glob(directory: path, include: ["*.xcodeproj"]).collect().first {
            try await defaultsController.setPackageDendencySCMToRegistryTransformation(.useRegistryIdentityAndSources)
            swiftPackageManagerPath = projectPath.appending(components: "project.xcworkspace", "xcshareddata", "swiftpm")
        } else {
            throw RegistryCommandSetupServiceError.noProjectFound(path)
        }

        let configurationJSONPath = swiftPackageManagerPath.appending(components: "configuration", "registries.json")
        if try await !fileSystem.exists(configurationJSONPath.parentDirectory) {
            try await fileSystem.makeDirectory(at: configurationJSONPath.parentDirectory)
        }
        if try await fileSystem.exists(configurationJSONPath) {
            try await fileSystem.remove(configurationJSONPath)
        }
        try await fileSystem.writeText(
            registryConfigurationJSON(
                serverURL: serverURL,
                accountHandle: accountHandle
            ),
            at: configurationJSONPath
        )

        ServiceContext.current?.alerts?.success(
            .alert(
                "Generated the \(accountHandle) registry configuration file at \(.accent(configurationJSONPath.relative(to: path).pathString))",
                nextSteps: [
                    "Commit the generated configuration file to share the configuration with the rest of your team",
                    "Ensure that your team members run \(.command("tuist registry login")) to log in to the registry",
                    "For more information about the registry, such as how to set up the registry in your CI, head to our \(.link(title: "docs", href: "https://docs.tuist.dev/en/guides/develop/registry"))",
                ]
            )
        )
    }

    private func path(_ path: String?) async throws -> AbsolutePath {
        if let path {
            return try await AbsolutePath(validating: path, relativeTo: fileSystem.currentWorkingDirectory())
        } else {
            return try await fileSystem.currentWorkingDirectory()
        }
    }

    private func registryConfigurationJSON(
        serverURL: URL,
        accountHandle: String
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
              "loginAPIPath": "/api/accounts/\(accountHandle)/registry/swift/login",
              "type": "token"
            }
          },
          "registries": {
            "[default]": {
              "supportsAvailability": false,
              "url": "\(serverURL.absoluteString.dropSuffix("/"))/api/accounts/\(accountHandle)/registry/swift"
            }
          },
          "version": 1
        }

        """
    }
}
