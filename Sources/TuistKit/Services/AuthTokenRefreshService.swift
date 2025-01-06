import FileSystem
import Foundation
import Mockable
import Path
import ServiceContextModule
import TuistCore
import TuistLoader
import TuistServer
import TuistSupport

@Mockable
protocol AuthTokenRefreshServicing: AnyObject {
    func run(
        directory: String?
    ) async throws
}

final class AuthTokenRefreshService: AuthTokenRefreshServicing {
    private let configLoader: ConfigLoading
    private let fileSystem: FileSysteming
    private let serverURLService: ServerURLServicing
    private let refreshAuthTokenService: RefreshAuthTokenServicing
    private let serverCredentialsStore: ServerCredentialsStoring
    private let serverSessionController: ServerSessionControlling
    private let serverAuthenticationController: ServerAuthenticationControlling

    // MARK: - Init

    init(
        configLoader: ConfigLoading = ConfigLoader(warningController: WarningController.shared),
        fileSystem: FileSysteming = FileSystem(),
        serverURLService: ServerURLServicing = ServerURLService(),
        refreshAuthTokenService: RefreshAuthTokenServicing = RefreshAuthTokenService(),
        serverCredentialsStore: ServerCredentialsStoring = ServerCredentialsStore(),
        serverSessionController: ServerSessionControlling = ServerSessionController(),
        serverAuthenticationController: ServerAuthenticationControlling = ServerAuthenticationController()
    ) {
        self.configLoader = configLoader
        self.fileSystem = fileSystem
        self.serverURLService = serverURLService
        self.refreshAuthTokenService = refreshAuthTokenService
        self.serverCredentialsStore = serverCredentialsStore
        self.serverSessionController = serverSessionController
        self.serverAuthenticationController = serverAuthenticationController
    }

    func run(
        directory: String?
    ) async throws {
        let directoryPath: AbsolutePath
        if let directory {
            directoryPath = try AbsolutePath(validating: directory, relativeTo: try await fileSystem.currentWorkingDirectory())
        } else {
            directoryPath = try await fileSystem.currentWorkingDirectory()
        }

        let config = try await configLoader.loadConfig(path: directoryPath)
        let serverURL = try serverURLService.url(configServerURL: config.url)

        guard let token = try await serverAuthenticationController.authenticationToken(serverURL: serverURL)
        else {
            throw ServerClientAuthenticationError.notAuthenticated
        }

        switch token {
        case let .user(legacyToken: legacyToken, accessToken: accessToken, refreshToken: refreshToken):
            if let refreshToken {
                try await fetchTokens(serverURL: serverURL, refreshToken: refreshToken.token)
            }
        case _:
            return
        }
    }

    func fetchTokens(serverURL: URL, refreshToken: String) async throws {
        do {
            let newTokens = try await RetryProvider()
                .runWithRetries {
                    return try await self.refreshAuthTokenService.refreshTokens(
                        serverURL: serverURL,
                        refreshToken: refreshToken
                    )
                }
            try await serverCredentialsStore
                .store(
                    credentials: ServerCredentials(
                        token: nil,
                        accessToken: newTokens.accessToken,
                        refreshToken: newTokens.refreshToken
                    ),
                    serverURL: serverURL
                )
        } catch {
            throw ServerClientAuthenticationError.notAuthenticated
        }
    }
}
