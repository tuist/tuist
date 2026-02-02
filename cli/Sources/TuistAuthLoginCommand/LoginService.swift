import Foundation
import TuistConstants
import TuistEnvironment
import TuistOIDC
import TuistServer

protocol LoginServicing: AnyObject {
    func run(
        email: String?,
        password: String?,
        serverURL: String?
    ) async throws
}

final class LoginService: LoginServicing {
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let userInputReader: UserInputReading
    private let authenticateService: AuthenticateServicing
    private let ciOIDCAuthenticator: CIOIDCAuthenticating
    private let exchangeOIDCTokenService: ExchangeOIDCTokenServicing

    init(
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        userInputReader: UserInputReading = UserInputReader(),
        authenticateService: AuthenticateServicing = AuthenticateService(),
        ciOIDCAuthenticator: CIOIDCAuthenticating = CIOIDCAuthenticator(),
        exchangeOIDCTokenService: ExchangeOIDCTokenServicing = ExchangeOIDCTokenService()
    ) {
        self.serverEnvironmentService = serverEnvironmentService
        self.userInputReader = userInputReader
        self.authenticateService = authenticateService
        self.ciOIDCAuthenticator = ciOIDCAuthenticator
        self.exchangeOIDCTokenService = exchangeOIDCTokenService
    }

    func run(
        email: String?,
        password: String?,
        serverURL: String?
    ) async throws {
        let resolvedServerURL: URL

        if let serverURL {
            guard let url = URL(string: serverURL) else {
                throw LoginServiceError.invalidServerURL(serverURL)
            }
            resolvedServerURL = try serverEnvironmentService.url(configServerURL: url)
        } else if let envURL = Environment.current.tuistVariables["URL"],
                  let url = URL(string: envURL)
        {
            resolvedServerURL = try serverEnvironmentService.url(configServerURL: url)
        } else {
            resolvedServerURL = Constants.URLs.production
        }

        if email != nil || password != nil {
            try await authenticateWithEmailAndPassword(
                email: email,
                password: password,
                serverURL: resolvedServerURL
            )
        } else if Environment.current.isCI {
            try await authenticateWithCIOIDC(serverURL: resolvedServerURL)
        } else {
            throw LoginServiceError.browserLoginNotSupported
        }
        print("Successfully logged in.")
    }

    private func authenticateWithCIOIDC(serverURL: URL) async throws {
        print("Detected CI environment, authenticating with OIDC...")

        let oidcToken = try await ciOIDCAuthenticator.fetchOIDCToken()
        let accessToken = try await exchangeOIDCTokenService.exchangeOIDCToken(
            oidcToken: oidcToken,
            serverURL: serverURL
        )

        try await ServerCredentialsStore.current.store(
            credentials: ServerCredentials(accessToken: accessToken),
            serverURL: serverURL
        )
    }

    private func authenticateWithEmailAndPassword(
        email: String?,
        password: String?,
        serverURL: URL
    ) async throws {
        let email = email ?? userInputReader.readString(asking: "Email:")
        let password = password ?? userInputReader.readString(asking: "Password:")

        let authenticationTokens = try await authenticateService.authenticate(
            email: email,
            password: password,
            serverURL: serverURL
        )

        try await ServerCredentialsStore.current.store(
            credentials: ServerCredentials(
                accessToken: authenticationTokens.accessToken,
                refreshToken: authenticationTokens.refreshToken
            ),
            serverURL: serverURL
        )
    }
}

enum LoginServiceError: LocalizedError, Equatable {
    case invalidServerURL(String)
    case browserLoginNotSupported

    var errorDescription: String? {
        switch self {
        case let .invalidServerURL(url):
            return "Invalid server URL: \(url)"
        case .browserLoginNotSupported:
            return """
            Browser-based login is not supported on Linux. Please use one of the following methods:
            - Pass --email and --password flags
            - Run in a supported CI environment (GitHub Actions, CircleCI, Bitrise) with OIDC configured
            - Set the TUIST_TOKEN environment variable with an account token
            """
        }
    }
}
