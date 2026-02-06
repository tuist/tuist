import Foundation
import Logging
import Path
import TSCBasic
import TuistCAS
import TuistConfigLoader
import TuistConstants
import TuistEncodable
import TuistEnvironment
import TuistHTTP
import TuistLogging
import TuistOIDC
import TuistServer

public protocol CacheConfigCommandServicing {
    func run(
        fullHandle: String,
        json: Bool,
        forceRefresh: Bool,
        directory: String?,
        url: String?
    ) async throws
}

public final class CacheConfigCommandService: CacheConfigCommandServicing {
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let serverAuthenticationController: ServerAuthenticationControlling
    private let ciOIDCAuthenticator: CIOIDCAuthenticating
    private let exchangeOIDCTokenService: ExchangeOIDCTokenServicing
    private let cacheURLStore: CacheURLStoring
    private let fullHandleService: FullHandleServicing
    private let configLoader: ConfigLoading

    public init(
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        serverAuthenticationController: ServerAuthenticationControlling = ServerAuthenticationController(),
        cacheURLStore: CacheURLStoring = CacheURLStore(),
        fullHandleService: FullHandleServicing = FullHandleService(),
        configLoader: ConfigLoading = ConfigLoader(),
        ciOIDCAuthenticator: CIOIDCAuthenticating = CIOIDCAuthenticator(),
        exchangeOIDCTokenService: ExchangeOIDCTokenServicing = ExchangeOIDCTokenService()
    ) {
        self.serverEnvironmentService = serverEnvironmentService
        self.serverAuthenticationController = serverAuthenticationController
        self.cacheURLStore = cacheURLStore
        self.fullHandleService = fullHandleService
        self.configLoader = configLoader
        self.ciOIDCAuthenticator = ciOIDCAuthenticator
        self.exchangeOIDCTokenService = exchangeOIDCTokenService
    }

    public func run(
        fullHandle: String,
        json: Bool,
        forceRefresh: Bool,
        directory: String?,
        url: String?
    ) async throws {
        let resolvedServerURL: URL

        if let url {
            guard let parsedURL = URL(string: url) else {
                throw CacheConfigCommandServiceError.invalidServerURL(url)
            }
            resolvedServerURL = parsedURL
        } else {
            let directoryPath: Path.AbsolutePath
            if let directory {
                let cwd = try await Environment.current.currentWorkingDirectory()
                directoryPath = try Path.AbsolutePath(validating: directory, relativeTo: cwd)
            } else {
                directoryPath = try await Environment.current.currentWorkingDirectory()
            }
            let config = try await configLoader.loadConfig(path: directoryPath)
            resolvedServerURL = try serverEnvironmentService.url(configServerURL: config.url)
        }

        let token = try await getAuthenticationToken(serverURL: resolvedServerURL, forceRefresh: forceRefresh)

        let (accountHandle, projectHandle) = try fullHandleService.parse(fullHandle)
        let cacheURL = try await cacheURLStore.getCacheURL(for: resolvedServerURL, accountHandle: accountHandle)

        let result = CacheConfiguration(
            url: cacheURL.absoluteString,
            token: token,
            accountHandle: accountHandle,
            projectHandle: projectHandle
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
              Token: \(result.token)
              Account: \(result.accountHandle)
              Project: \(result.projectHandle)
            """)
        }
    }

    private func getAuthenticationToken(serverURL: URL, forceRefresh: Bool) async throws -> String {
        if forceRefresh {
            try await serverAuthenticationController.refreshToken(serverURL: serverURL)
        }

        if let existingToken = try await serverAuthenticationController.authenticationToken(serverURL: serverURL) {
            return existingToken.value
        }

        if Environment.current.isCI, let oidcToken = try? await authenticateWithOIDC(serverURL: serverURL) {
            return oidcToken
        }

        throw CacheConfigCommandServiceError.notAuthenticated
    }

    private func authenticateWithOIDC(serverURL: URL) async throws -> String {
        let oidcToken = try await ciOIDCAuthenticator.fetchOIDCToken()
        let accessToken = try await exchangeOIDCTokenService.exchangeOIDCToken(
            oidcToken: oidcToken,
            serverURL: serverURL
        )

        try await ServerCredentialsStore.current.store(
            credentials: ServerCredentials(accessToken: accessToken),
            serverURL: serverURL
        )

        return accessToken
    }
}

struct CacheConfiguration: Codable {
    let url: String
    let token: String
    let accountHandle: String
    let projectHandle: String

    enum CodingKeys: String, CodingKey {
        case url
        case token
        case accountHandle = "account_handle"
        case projectHandle = "project_handle"
    }
}

public enum CacheConfigCommandServiceError: LocalizedError, Equatable {
    case notAuthenticated
    case invalidServerURL(String)

    public var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return
                "You are not authenticated. Refer to the documentation for authentication options: https://docs.tuist.dev/en/guides/server/authentication"
        case let .invalidServerURL(url):
            return "Invalid server URL: \(url)"
        }
    }
}
