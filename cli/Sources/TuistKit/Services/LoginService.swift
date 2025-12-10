import Foundation
import Mockable
import Noora
import Path
import TuistCore
import TuistLoader
import TuistOIDC
import TuistServer
import TuistSupport

@Mockable
protocol LoginServicing: AnyObject {
    func run(
        email: String?,
        password: String?,
        directory: String?,
        onEvent: @escaping (LoginServiceEvent) async -> Void
    ) async throws
}

enum LoginServiceEvent: CustomStringConvertible {
    case openingBrowser(URL)
    case waitForAuthentication
    case oidcAuthenticating
    case completed

    var description: String {
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

final class LoginService: LoginServicing {
    private let serverSessionController: ServerSessionControlling
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading
    private let userInputReader: UserInputReading
    private let authenticateService: AuthenticateServicing
    private let ciOIDCAuthenticator: CIOIDCAuthenticating
    private let exchangeOIDCTokenService: ExchangeOIDCTokenServicing

    init(
        serverSessionController: ServerSessionControlling = ServerSessionController(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader(),
        userInputReader: UserInputReading = UserInputReader(),
        authenticateService: AuthenticateServicing = AuthenticateService(),
        ciOIDCAuthenticator: CIOIDCAuthenticating = CIOIDCAuthenticator(),
        exchangeOIDCTokenService: ExchangeOIDCTokenServicing = ExchangeOIDCTokenService()
    ) {
        self.serverSessionController = serverSessionController
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
        self.userInputReader = userInputReader
        self.authenticateService = authenticateService
        self.ciOIDCAuthenticator = ciOIDCAuthenticator
        self.exchangeOIDCTokenService = exchangeOIDCTokenService
    }

    // MARK: - AuthServicing

    func run(
        email: String?,
        password: String?,
        directory: String?,
        onEvent: @escaping (LoginServiceEvent) async -> Void
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

        if email != nil || password != nil {
            try await authenticateWithEmailAndPassword(
                email: email,
                password: password,
                serverURL: serverURL
            )
        } else if Environment.current.isCI {
            try await authenticateWithCIOIDC(serverURL: serverURL, onEvent: onEvent)
        } else {
            try await authenticateWithBrowserLogin(serverURL: serverURL, onEvent: onEvent)
        }
        await onEvent(.completed)
    }

    private func authenticateWithCIOIDC(
        serverURL: URL,
        onEvent: @escaping (LoginServiceEvent) async -> Void
    ) async throws {
        await onEvent(.oidcAuthenticating)

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

    private func authenticateWithBrowserLogin(
        serverURL: URL,
        onEvent: @escaping (LoginServiceEvent) async -> Void
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

extension LoginServicing {
    func run(
        email: String? = nil,
        password: String? = nil,
        directory: String? = nil
    ) async throws {
        try await run(
            email: email, password: password, directory: directory,
            onEvent: Self.defaultOnEvent(event:)
        )
    }

    private static func defaultOnEvent(event: LoginServiceEvent) {
        switch event {
        case .completed:
            AlertController.current.success(.alert("\(event.description)"))
        case .oidcAuthenticating, .openingBrowser, .waitForAuthentication:
            Noora.current.info(.init(stringLiteral: event.description))
        }
    }
}
