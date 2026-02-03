import Foundation
import Path
import TuistCAS
import TuistLoader
import TuistOIDC
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
    private let ciOIDCAuthenticator: CIOIDCAuthenticating
    private let exchangeOIDCTokenService: ExchangeOIDCTokenServicing

    init(
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        serverAuthenticationController: ServerAuthenticationControlling = ServerAuthenticationController(),
        cacheURLStore: CacheURLStoring = CacheURLStore(),
        configLoader: ConfigLoading = ConfigLoader(),
        ciOIDCAuthenticator: CIOIDCAuthenticating = CIOIDCAuthenticator(),
        exchangeOIDCTokenService: ExchangeOIDCTokenServicing = ExchangeOIDCTokenService()
    ) {
        self.serverEnvironmentService = serverEnvironmentService
        self.serverAuthenticationController = serverAuthenticationController
        self.cacheURLStore = cacheURLStore
        self.configLoader = configLoader
        self.ciOIDCAuthenticator = ciOIDCAuthenticator
        self.exchangeOIDCTokenService = exchangeOIDCTokenService
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

        let token = try await getAuthenticationToken(serverURL: resolvedServerURL)

        let accountHandle = fullHandle.split(separator: "/").first.map(String.init)
        let cacheURL = try await cacheURLStore.getCacheURL(for: resolvedServerURL, accountHandle: accountHandle)

        let result = CacheConfiguration(
            url: cacheURL.absoluteString,
            token: token,
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

    private func getAuthenticationToken(serverURL: URL) async throws -> String {
        // 1. Check for TUIST_TOKEN environment variable (account token)
        if let accountToken = Environment.current.tuistVariables[Constants.EnvironmentVariables.token] {
            return accountToken
        }

        // 2. Check for existing valid authentication token
        if let existingToken = try await serverAuthenticationController.authenticationToken(serverURL: serverURL) {
            return existingToken.value
        }

        // 3. Try OIDC authentication if in a supported CI environment
        if let oidcToken = try? await authenticateWithOIDC(serverURL: serverURL) {
            return oidcToken
        }

        throw CacheConfigServiceError.notAuthenticated
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

enum CacheConfigServiceError: LocalizedError, Equatable {
    case notAuthenticated
    case invalidServerURL(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return """
            You are not authenticated. To authenticate, either:
            - Set the TUIST_TOKEN environment variable with an account token
            - Run `tuist auth login` to authenticate interactively
            - Run in a supported CI environment (GitHub Actions, CircleCI, Bitrise) with OIDC configured
            """
        case let .invalidServerURL(url):
            return "Invalid server URL: \(url)"
        }
    }
}
