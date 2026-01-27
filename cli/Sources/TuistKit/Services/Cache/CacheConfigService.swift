import Foundation
import Path
import TuistCAS
import TuistLoader
import TuistServer
import TuistSupport

protocol CacheConfigServicing {
    func run(
        fullHandle: String,
        json: Bool,
        directory: String?,
        serverURL: String?
    ) async throws
}

final class CacheConfigService: CacheConfigServicing {
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
        directory: String?,
        serverURL: String?
    ) async throws {
        let resolvedServerURL: URL

        if let serverURL {
            guard let url = URL(string: serverURL) else {
                throw CacheConfigServiceError.invalidServerURL(serverURL)
            }
            resolvedServerURL = url
        } else {
            let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(directory)
            let config = try await configLoader.loadConfig(path: directoryPath)
            resolvedServerURL = try serverEnvironmentService.url(configServerURL: config.url)
        }

        guard let token = try await serverAuthenticationController.authenticationToken(serverURL: resolvedServerURL)
        else {
            throw CacheConfigServiceError.notAuthenticated
        }

        let accountHandle = fullHandle.split(separator: "/").first.map(String.init)
        let cacheURL = try await cacheURLStore.getCacheURL(for: resolvedServerURL, accountHandle: accountHandle)

        let result = CacheConfiguration(
            url: cacheURL.absoluteString,
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
            Remote Cache Configuration:
              URL: \(result.url)
              Token: \(String(result.token.prefix(20)))...
              Account: \(result.accountHandle)
              Project: \(result.projectHandle)
            """)
        }
    }
}

struct CacheConfiguration: Codable {
    let url: String
    let token: String
    let accountHandle: String
    let projectHandle: String
}

enum CacheConfigServiceError: LocalizedError, Equatable {
    case notAuthenticated
    case invalidServerURL(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You are not authenticated. Please run `tuist auth` first."
        case let .invalidServerURL(url):
            return "Invalid server URL: \(url)"
        }
    }
}
