import FileSystem
import Foundation
import Path
import TuistConstants
import TuistSupport

public protocol RegistryConfigurationGenerating {
    func generate(
        at configurationPath: AbsolutePath,
        serverURL: URL
    ) async throws
}

public struct RegistryConfigurationGenerator: RegistryConfigurationGenerating {
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
        let registryURL = Constants.URLs.swiftRegistry(for: serverURL)
        let registryHost = registryURL.host() ?? Constants.URLs.swiftRegistry(for: Constants.URLs.production).host()!

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
            "\(registryHost)": {
              "loginAPIPath": "/login",
              "type": "token"
            }
          },
          "registries": {
            "[default]": {
              "supportsAvailability": false,
              "url": "\(registryURL.absoluteString.dropSuffix("/"))"
            }
          },
          "version": 1
        }

        """
    }
}
