import Foundation
import Mockable
import TuistConstants
import TuistEnvironment
import TuistOIDC
import TuistServer
import TuistUserInputReader

@Mockable
public protocol LoginCommandServicing {
    func run(
        email: String?,
        password: String?,
        serverURL: String?,
        onEvent: @escaping (LoginCommandServiceEvent) async -> Void
    ) async throws
}

public enum LoginCommandServiceEvent: CustomStringConvertible {
    case openingBrowser(URL)
    case waitForAuthentication
    case oidcAuthenticating
    case completed

    public var description: String {
        switch self {
        case let .openingBrowser(url):
            "Opening \(url.absoluteString) to start the authentication flow"
        case .waitForAuthentication:
            "Press CTRL + C once to cancel the process."
        case .oidcAuthenticating:
            "Detected CI environment, authenticating with OIDC..."
        case .completed:
            "Successfully logged in."
        }
    }
}

public struct LoginCommandService: LoginCommandServicing {
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let serverSessionController: ServerSessionControlling
    private let userInputReader: UserInputReading
    private let authenticateService: AuthenticateServicing
    private let ciOIDCAuthenticator: CIOIDCAuthenticating
    private let exchangeOIDCTokenService: ExchangeOIDCTokenServicing
    private let retryProvider: RetryProviding

    public init(
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        serverSessionController: ServerSessionControlling = ServerSessionController(),
        userInputReader: UserInputReading = UserInputReader(),
        authenticateService: AuthenticateServicing = AuthenticateService(),
        ciOIDCAuthenticator: CIOIDCAuthenticating = CIOIDCAuthenticator(),
        exchangeOIDCTokenService: ExchangeOIDCTokenServicing = ExchangeOIDCTokenService(),
        retryProvider: RetryProviding = RetryProvider()
    ) {
        self.serverEnvironmentService = serverEnvironmentService
        self.serverSessionController = serverSessionController
        self.userInputReader = userInputReader
        self.authenticateService = authenticateService
        self.ciOIDCAuthenticator = ciOIDCAuthenticator
        self.exchangeOIDCTokenService = exchangeOIDCTokenService
        self.retryProvider = retryProvider
    }

    public func run(
        email: String?,
        password: String?,
        serverURL: String?,
        onEvent: @escaping (LoginCommandServiceEvent) async -> Void
    ) async throws {
        let resolvedServerURL: URL

        if let serverURL {
            guard let url = URL(string: serverURL) else {
                throw LoginCommandServiceError.invalidServerURL(serverURL)
            }
            resolvedServerURL = try serverEnvironmentService.url(configServerURL: url)
        } else if let envURL = Environment.current.tuistVariables["TUIST_URL"],
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
            try await authenticateWithCIOIDC(serverURL: resolvedServerURL, onEvent: onEvent)
        } else {
            try await authenticateWithBrowserLogin(serverURL: resolvedServerURL, onEvent: onEvent)
        }
        await onEvent(.completed)
    }

    private func authenticateWithCIOIDC(
        serverURL: URL,
        onEvent: @escaping (LoginCommandServiceEvent) async -> Void
    ) async throws {
        await onEvent(.oidcAuthenticating)

        let oidcToken = try await ciOIDCAuthenticator.fetchOIDCToken()
        let accessToken = try await retryProvider.runWithRetries {
            try await exchangeOIDCTokenService.exchangeOIDCToken(
                oidcToken: oidcToken,
                serverURL: serverURL
            )
        }

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

    private func authenticateWithBrowserLogin(
        serverURL: URL,
        onEvent: @escaping (LoginCommandServiceEvent) async -> Void
    ) async throws {
        try await serverSessionController.authenticate(
            serverURL: serverURL,
            deviceCodeType: .cli,
            onOpeningBrowser: { authURL in
                await onEvent(.openingBrowser(authURL))
            },
            onAuthWaitBegin: {
                await onEvent(.waitForAuthentication)
            }
        )
    }
}

extension LoginCommandServicing {
    public func run(
        email: String? = nil,
        password: String? = nil,
        serverURL: String? = nil
    ) async throws {
        try await run(
            email: email,
            password: password,
            serverURL: serverURL,
            onEvent: { event in
                print(event.description)
            }
        )
    }
}

enum LoginCommandServiceError: LocalizedError, Equatable {
    case invalidServerURL(String)

    var errorDescription: String? {
        switch self {
        case let .invalidServerURL(url):
            return "Invalid server URL: \(url)"
        }
    }
}
