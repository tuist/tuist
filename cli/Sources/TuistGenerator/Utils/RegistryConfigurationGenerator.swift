import FileSystem
import Foundation
import Path
import TuistSupport

public protocol RegistryConfigurationGenerating {
    func generate(
        at configurationPath: AbsolutePath,
        serverURL: URL
    ) async throws
}

public final class RegistryConfigurationGenerator: RegistryConfigurationGenerating {
    private let fileSystem: FileSysteming

    public init(fileSystem: FileSysteming = FileSystem()) {
        self.fileSystem = fileSystem
    }

    public func generate(
        at configurationPath: AbsolutePath,
        serverURL: URL
    ) async throws {
        let registriesJSONPath = configurationPath.appending(component: "registries.json")

        if try await !fileSystem.exists(configurationPath) {
            try await fileSystem.makeDirectory(at: configurationPath)
        }

        if try await fileSystem.exists(registriesJSONPath) {
            try await fileSystem.remove(registriesJSONPath)
        }

        try await fileSystem.writeText(
            Self.registryConfigurationJSON(serverURL: serverURL),
            at: registriesJSONPath
        )
    }

    public static func registryConfigurationJSON(serverURL: URL) -> String {
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
