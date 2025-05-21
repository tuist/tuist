import Foundation
import Mockable
import Path
import TuistCore
import TuistLoader
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
    case completed

    var description: String {
        switch self {
        case let .openingBrowser(url):
            "Opening \(url.absoluteString) to start the authentication flow"
        case .waitForAuthentication:
            "Press CTRL + C once to cancel the process."
        case .completed:
            "Successfully logged in."
        }
    }
}

final class LoginService: LoginServicing {
    private let serverSessionController: ServerSessionControlling
    private let serverURLService: ServerURLServicing
    private let configLoader: ConfigLoading
    private let userInputReader: UserInputReading
    private let authenticateService: AuthenticateServicing
    private let serverCredentialsStore: ServerCredentialsStoring

    init(
        serverSessionController: ServerSessionControlling = ServerSessionController(),
        serverURLService: ServerURLServicing = ServerURLService(),
        configLoader: ConfigLoading = ConfigLoader(),
        userInputReader: UserInputReading = UserInputReader(),
        authenticateService: AuthenticateServicing = AuthenticateService(),
        serverCredentialsStore: ServerCredentialsStoring = ServerCredentialsStore()
    ) {
        self.serverSessionController = serverSessionController
        self.serverURLService = serverURLService
        self.configLoader = configLoader
        self.userInputReader = userInputReader
        self.authenticateService = authenticateService
        self.serverCredentialsStore = serverCredentialsStore
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
            directoryPath = try AbsolutePath(validating: directory, relativeTo: FileHandler.shared.currentPath)
        } else {
            directoryPath = FileHandler.shared.currentPath
        }
        let config = try await configLoader.loadConfig(path: directoryPath)
        let serverURL = try serverURLService.url(configServerURL: config.url)

        if email != nil || password != nil {
            try await authenticateWithEmailAndPassword(
                email: email,
                password: password,
                serverURL: serverURL
            )
        } else {
            try await authenticateWithBrowserLogin(serverURL: serverURL, onEvent: onEvent)
        }
        await onEvent(.completed)
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

        try await serverCredentialsStore.store(
            credentials: ServerCredentials(
                token: nil,
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
        try await run(email: email, password: password, directory: directory, onEvent: Self.defaultOnEvent(event:))
    }

    private static func defaultOnEvent(event: LoginServiceEvent) {
        switch event {
        case .completed:
            AlertController.current.success(.alert("\(event.description)"))
        default:
            Logger.current.notice("\(event.description)")
        }
    }
}
