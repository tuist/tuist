import Foundation
import Logging
import TSCBasic
import TuistConstants
import TuistEnvironment
import TuistLogging
import TuistOIDC
import TuistServer

protocol CacheConfigServicing {
    func run(
        fullHandle: String,
        json: Bool,
        serverURL: String?
    ) async throws
}

final class CacheConfigService: CacheConfigServicing {
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let serverAuthenticationController: ServerAuthenticationControlling
    private let cacheURLStore: CacheURLStoring
    private let ciOIDCAuthenticator: CIOIDCAuthenticating
    private let exchangeOIDCTokenService: ExchangeOIDCTokenServicing

    init(
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        serverAuthenticationController: ServerAuthenticationControlling = ServerAuthenticationController(),
        cacheURLStore: CacheURLStoring = CacheURLStore(),
        ciOIDCAuthenticator: CIOIDCAuthenticating = CIOIDCAuthenticator(),
        exchangeOIDCTokenService: ExchangeOIDCTokenServicing = ExchangeOIDCTokenService()
    ) {
        self.serverEnvironmentService = serverEnvironmentService
        self.serverAuthenticationController = serverAuthenticationController
        self.cacheURLStore = cacheURLStore
        self.ciOIDCAuthenticator = ciOIDCAuthenticator
        self.exchangeOIDCTokenService = exchangeOIDCTokenService
    }

    func run(
        fullHandle: String,
        json: Bool,
        serverURL: String?
    ) async throws {
        let resolvedServerURL: URL

        if let serverURL {
            guard let url = URL(string: serverURL) else {
                throw CacheConfigServiceError.invalidServerURL(serverURL)
            }
            resolvedServerURL = url
        } else if let envURL = Environment.current.tuistVariables["URL"],
                  let url = URL(string: envURL)
        {
            resolvedServerURL = try serverEnvironmentService.url(configServerURL: url)
        } else {
            resolvedServerURL = Constants.URLs.production
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
        if let accountToken = Environment.current.tuistVariables[Constants.EnvironmentVariables.token] {
            return accountToken
        }

        if let existingToken = try await serverAuthenticationController.authenticationToken(serverURL: serverURL) {
            return existingToken.value
        }

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
