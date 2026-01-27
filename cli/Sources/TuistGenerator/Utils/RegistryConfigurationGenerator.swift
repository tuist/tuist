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
        let registryURL = if serverURL.host() == "tuist.dev" {
            "https://registry.tuist.dev/api/registry/swift"
        } else {
            var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false)
            components?.path = "/api/registry/swift"
            components?.query = nil
            components?.fragment = nil
            return components?.string ?? "\(serverURL.absoluteString.dropSuffix("/"))/api/registry/swift"
        }

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
              "url": "\(registryURL)"
            }
          },
          "version": 1
        }

        """
    }
}
