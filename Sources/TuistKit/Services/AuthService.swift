import Foundation
import Mockable
import Path
import TuistCore
import TuistLoader
import TuistServer
import TuistSupport

@Mockable
protocol AuthServicing: AnyObject {
    func authenticate(
        email: String?,
        password: String?,
        directory: String?
    ) async throws
}

final class AuthService: AuthServicing {
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

    func authenticate(
        email: String?,
        password: String?,
        directory: String?
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
            try await authenticateWithBrowserLogin(serverURL: serverURL)
        }
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

        try serverCredentialsStore.store(
            credentials: ServerCredentials(
                token: nil,
                accessToken: authenticationTokens.accessToken,
                refreshToken: authenticationTokens.refreshToken
            ),
            serverURL: serverURL
        )
        logger.notice("Credentials stored successfully.", metadata: .success)
    }

    private func authenticateWithBrowserLogin(
        serverURL: URL
    ) async throws {
        try await serverSessionController.authenticate(serverURL: serverURL)
    }
}
