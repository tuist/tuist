import FileSystem
import Foundation
import Path
import ServiceContextModule
import TuistLoader
import TuistServer
import TuistSupport

enum RegistrySetupServiceError: Equatable, FatalError {
    case missingFullHandle
    case noProjectFound(AbsolutePath)

    var type: TuistSupport.ErrorType {
        switch self {
        case .missingFullHandle, .noProjectFound: .abort
        }
    }

    var description: String {
        switch self {
        case .missingFullHandle:
            return "We couldn't set up the registry because the project is missing the 'fullHandle' in the 'Tuist.swift' file."
        case let .noProjectFound(path):
            return "We couldn't find an Xcode, SwiftPM, or Tuist project at \(path.pathString). Make sure you're in the right directory."
        }
    }
}

final class RegistrySetupService {
    private let serverURLService: ServerURLServicing
    private let configLoader: ConfigLoading
    private let fileSystem: FileSysteming
    private let fullHandleService: FullHandleServicing
    private let manifestFilesLocator: ManifestFilesLocating

    init(
        serverURLService: ServerURLServicing = ServerURLService(),
        configLoader: ConfigLoading = ConfigLoader(),
        fileSystem: FileSysteming = FileSystem(),
        fullHandleService: FullHandleServicing = FullHandleService(),
        manifestFilesLocator: ManifestFilesLocating = ManifestFilesLocator()
    ) {
        self.serverURLService = serverURLService
        self.configLoader = configLoader
        self.fileSystem = fileSystem
        self.fullHandleService = fullHandleService
        self.manifestFilesLocator = manifestFilesLocator
    }

    func run(
        path: String?
    ) async throws {
        let path = try await self.path(path)
        let config = try await configLoader.loadConfig(path: path)

        guard let fullHandle = config.fullHandle else { throw RegistrySetupServiceError.missingFullHandle }
        let accountHandle = try fullHandleService.parse(fullHandle).accountHandle

        ServiceContext.current?.logger?.info("Logging into the registry...")
        let serverURL = try serverURLService.url(configServerURL: config.url)

        let swiftPackageManagerPath: AbsolutePath

        if let directoryWithPackageManifest = try await manifestFilesLocator.locatePackageManifest(at: path)?.parentDirectory {
            swiftPackageManagerPath = directoryWithPackageManifest.appending(component: ".swiftpm")
        } else if let workspacePath = try await fileSystem.glob(directory: path, include: ["*.xcworkspace"]).collect().first {
            swiftPackageManagerPath = workspacePath.appending(components: "xcshareddata", "swiftpm")
        } else if let projectPath = try await fileSystem.glob(directory: path, include: ["*.xcodeproj"]).collect().first {
            swiftPackageManagerPath = projectPath.appending(components: "project.xcworkspace", "xcshareddata", "swiftpm")
        } else {
            throw RegistrySetupServiceError.noProjectFound(path)
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

        ServiceContext.current?.logger?.info("""
        Generated the \(accountHandle) registry configuration file at \(configurationJSONPath).
        Make sure to commit this file to share the configuration with the rest of your team.
        To log in to the registry, run 'tuist registry login'.
        """)
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
            "canary.tuist.dev": {
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
