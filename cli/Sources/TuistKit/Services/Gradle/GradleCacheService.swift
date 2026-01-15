import Foundation
import Path
import TuistCAS
import TuistLoader
import TuistServer
import TuistSupport

protocol GradleCacheServicing {
    func run(
        fullHandle: String,
        json: Bool,
        directory: String?
    ) async throws
}

final class GradleCacheService: GradleCacheServicing {
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let serverAuthenticationController: ServerAuthenticationControlling
    private let cacheURLStore: CacheURLStoring
    private let configLoader: ConfigLoading

    init(
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        serverAuthenticationController: ServerAuthenticationControlling = ServerAuthenticationController(),
        cacheURLStore: CacheURLStoring = CacheURLStore(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.serverEnvironmentService = serverEnvironmentService
        self.serverAuthenticationController = serverAuthenticationController
        self.cacheURLStore = cacheURLStore
        self.configLoader = configLoader
    }

    func run(
        fullHandle: String,
        json: Bool,
        directory: String?
    ) async throws {
        let directoryPath: AbsolutePath
        if let directory {
            directoryPath = try AbsolutePath(
                validating: directory, relativeTo: FileHandler.shared.currentPath
            )
        } else {
            directoryPath = FileHandler.shared.currentPath
        }

        let config = try await configLoader.loadConfig(path: directoryPath)
        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        guard let token = try await serverAuthenticationController.authenticationToken(serverURL: serverURL) else {
            throw GradleCacheServiceError.notAuthenticated
        }

        let accountHandle = fullHandle.split(separator: "/").first.map(String.init)
        let cacheURL = try await cacheURLStore.getCacheURL(for: serverURL, accountHandle: accountHandle)

        let gradleCacheURL = cacheURL.appendingPathComponent("api/cache/gradle")

        let result = GradleCacheConfiguration(
            endpoint: gradleCacheURL.absoluteString,
            token: token.value,
            accountHandle: accountHandle ?? "",
            projectHandle: fullHandle.split(separator: "/").dropFirst().joined(separator: "/")
        )

        if json {
            let jsonOutput = try result.toJSON()
            Logger.current.info(
                .init(stringLiteral: jsonOutput.toString(prettyPrint: true)), metadata: .json
            )
        } else {
            Logger.current.info("""
            Gradle Build Cache Configuration:
              Endpoint: \(result.endpoint)
              Token: \(String(result.token.prefix(20)))...
              Account: \(result.accountHandle)
              Project: \(result.projectHandle)

            Add the following to your settings.gradle.kts:

              buildCache {
                  remote<HttpBuildCache> {
                      url = uri("\(result.endpoint)")
                      credentials {
                          username = "tuist"
                          password = "\(result.token)"
                      }
                      isPush = true
                  }
              }
            """)
        }
    }
}

struct GradleCacheConfiguration: Codable {
    let endpoint: String
    let token: String
    let accountHandle: String
    let projectHandle: String
}

enum GradleCacheServiceError: LocalizedError, Equatable {
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You are not authenticated. Please run `tuist auth` first."
        }
    }
}
