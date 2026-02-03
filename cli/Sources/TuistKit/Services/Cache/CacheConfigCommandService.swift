import Foundation
import TuistCAS
import TuistEnvironment
import TuistHTTP
import TuistLogging
import TuistOIDC
import TuistServer
import TuistSupport

protocol CacheConfigCommandServicing {
    func run(
        fullHandle: String,
        json: Bool,
        forceRefresh: Bool,
        url: String?
    ) async throws
}

struct CacheConfigCommandService: CacheConfigCommandServicing {
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let serverAuthenticationController: ServerAuthenticationControlling
    private let cacheURLStore: CacheURLStoring
    private let fullHandleService: FullHandleServicing
    private let ciOIDCAuthenticator: CIOIDCAuthenticating
    private let exchangeOIDCTokenService: ExchangeOIDCTokenServicing

    init(
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        serverAuthenticationController: ServerAuthenticationControlling = ServerAuthenticationController(),
        cacheURLStore: CacheURLStoring = CacheURLStore(),
        fullHandleService: FullHandleServicing = FullHandleService(),
        ciOIDCAuthenticator: CIOIDCAuthenticating = CIOIDCAuthenticator(),
        exchangeOIDCTokenService: ExchangeOIDCTokenServicing = ExchangeOIDCTokenService()
    ) {
        self.serverEnvironmentService = serverEnvironmentService
        self.serverAuthenticationController = serverAuthenticationController
        self.cacheURLStore = cacheURLStore
        self.fullHandleService = fullHandleService
        self.ciOIDCAuthenticator = ciOIDCAuthenticator
        self.exchangeOIDCTokenService = exchangeOIDCTokenService
    }

    func run(
        fullHandle: String,
        json: Bool,
        forceRefresh: Bool,
        url: String?
    ) async throws {
        let resolvedServerURL: URL

        if let url {
            guard let parsedURL = URL(string: url) else {
                throw CacheConfigCommandServiceError.invalidServerURL(url)
            }
            resolvedServerURL = parsedURL
        } else {
            resolvedServerURL = serverEnvironmentService.url()
        }

        let token = try await getAuthenticationToken(serverURL: resolvedServerURL, forceRefresh: forceRefresh)

        let (accountHandle, projectHandle) = try fullHandleService.parse(fullHandle)
        let cacheURL = try await cacheURLStore.getCacheURL(for: resolvedServerURL, accountHandle: accountHandle)

        let cacheConfiguration = CacheConfiguration(
            url: cacheURL.absoluteString,
            token: token,
            accountHandle: accountHandle,
            projectHandle: projectHandle
        )

        if json {
            let jsonOutput = try cacheConfiguration.toJSON()
            Logger.current.info(
                .init(stringLiteral: jsonOutput.toString(prettyPrint: true)), metadata: .json
            )
        } else {
            Logger.current.info("""
            Remote Cache Configuration:
              URL: \(cacheConfiguration.url)
              Token: \(cacheConfiguration.token)
              Account: \(cacheConfiguration.accountHandle)
              Project: \(cacheConfiguration.projectHandle)
            """)
        }
    }

    private func getAuthenticationToken(serverURL: URL, forceRefresh: Bool) async throws -> String {
        // 1. Force refresh if requested
        if forceRefresh {
            try await serverAuthenticationController.refreshToken(serverURL: serverURL)
        }

        // 2. Check for existing valid authentication token (also checks TUIST_TOKEN env var)
        if let existingToken = try await serverAuthenticationController.authenticationToken(serverURL: serverURL) {
            return existingToken.value
        }

        // 3. Try OIDC authentication if in a CI environment
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

        // Store the credentials for future use within this session
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

enum CacheConfigCommandServiceError: LocalizedError, Equatable {
    case notAuthenticated
    case invalidServerURL(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You are not authenticated. Refer to the documentation for authentication options: https://docs.tuist.dev/en/guides/server/authentication"
        case let .invalidServerURL(url):
            return "Invalid server URL: \(url)"
        }
    }
}
