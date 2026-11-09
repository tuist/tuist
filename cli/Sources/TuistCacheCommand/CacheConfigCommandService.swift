import ArgumentParser
import Foundation
import Noora
import Path
import TuistCAS
import TuistConfig
import TuistConfigLoader
import TuistConstants
import TuistEnvironment
import TuistHTTP
import TuistServer

public protocol CacheConfigCommandServicing {
    func run(
        fullHandle: String?,
        json: Bool,
        forceRefresh: Bool,
        directory: String?,
        url: String?
    ) async throws
}

public struct CacheConfigCommandService: CacheConfigCommandServicing {
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let serverAuthenticationController: ServerAuthenticationControlling
    private let getCacheTokenService: GetCacheTokenServicing
    private let cacheURLStore: CacheURLStoring
    private let fullHandleService: FullHandleServicing
    private let configLoader: ConfigLoading

    public init(
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        serverAuthenticationController: ServerAuthenticationControlling = ServerAuthenticationController(),
        cacheURLStore: CacheURLStoring = CacheURLStore(),
        getCacheTokenService: GetCacheTokenServicing = GetCacheTokenService(),
        fullHandleService: FullHandleServicing = FullHandleService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.serverEnvironmentService = serverEnvironmentService
        self.serverAuthenticationController = serverAuthenticationController
        self.cacheURLStore = cacheURLStore
        self.getCacheTokenService = getCacheTokenService
        self.fullHandleService = fullHandleService
        self.configLoader = configLoader
    }

    public func run(
        fullHandle: String?,
        json: Bool,
        forceRefresh: Bool,
        directory: String?,
        url: String?
    ) async throws {
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(directory)

        let config = try await configLoader.loadConfig(path: directoryPath)

        let resolvedServerURL: URL
        if let url {
            guard let parsedURL = URL(string: url) else {
                throw CacheConfigCommandServiceError.invalidServerURL(url)
            }
            resolvedServerURL = parsedURL
        } else {
            resolvedServerURL = try serverEnvironmentService.url(configServerURL: config.url)
        }

        let resolvedFullHandle = fullHandle ?? config.fullHandle
        guard let resolvedFullHandle else {
            throw CacheConfigCommandServiceError.missingFullHandle
        }

        let networkTrusted = try await ServerCacheAccessMode.usesNetworkTrust(
            serverURL: resolvedServerURL, authenticationController: serverAuthenticationController
        )
        if !networkTrusted {
            try await ensureAuthenticated(serverURL: resolvedServerURL, forceRefresh: forceRefresh)
        }

        let (accountHandle, projectHandle) = try fullHandleService.parse(resolvedFullHandle)
        let cacheURL = try await cacheURLStore.getCacheURL(for: resolvedServerURL, accountHandle: accountHandle)

        if networkTrusted { try ServerReportPublishingMode.validateDestination(cacheURL) }
        let token = networkTrusted ? "" : try await getCacheTokenService.getCacheToken(
            serverURL: resolvedServerURL, fullHandle: resolvedFullHandle
        ).token

        let result = CacheConfiguration(
            url: cacheURL.absoluteString,
            endpoints: [cacheURL.absoluteString],
            token: token,
            accountHandle: accountHandle,
            projectHandle: projectHandle
        )

        if json {
            try Noora.current.json(result)
        } else {
            Noora.current.passthrough("""
            Remote Cache Configuration:
              URL: \(result.url)
              Token: \(result.token)
              Account: \(result.accountHandle)
              Project: \(result.projectHandle)
            """)
        }
    }

    /// A signed-out CLI with a workload identity (CI, Amp orbs) signs itself in during the token
    /// lookup, so there is no separate OIDC step here.
    private func ensureAuthenticated(serverURL: URL, forceRefresh: Bool) async throws {
        if forceRefresh {
            try await serverAuthenticationController.refreshToken(serverURL: serverURL)
        }

        if try await serverAuthenticationController.authenticationToken(serverURL: serverURL) == nil {
            throw CacheConfigCommandServiceError.notAuthenticated
        }
    }
}

struct CacheConfiguration: Codable {
    let url: String
    /// The locally resolved endpoint, retaining the legacy JSON array shape.
    let endpoints: [String]
    let token: String
    let accountHandle: String
    let projectHandle: String

    enum CodingKeys: String, CodingKey {
        case url
        case endpoints
        case token
        case accountHandle = "account_handle"
        case projectHandle = "project_handle"
    }
}

public enum CacheConfigCommandServiceError: LocalizedError, Equatable {
    case notAuthenticated
    case invalidServerURL(String)
    case missingFullHandle

    public var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return
                "You are not authenticated. Refer to the documentation for authentication options: https://tuist.dev/en/docs/guides/server/authentication"
        case let .invalidServerURL(url):
            return "Invalid server URL: \(url)"
        case .missingFullHandle:
            return
                "The project full handle is required. Provide it as an argument or set 'project' in your tuist.toml."
        }
    }
}
