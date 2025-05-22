import FileSystem
import Foundation
import Mockable

@Mockable
public protocol AuthTokenRefreshServicing {
    func refreshTokens(
        serverURL: URL
    ) async throws
}

public struct AuthTokenRefreshService: AuthTokenRefreshServicing {
    private let fileSystem: FileSysteming
    private let refreshAuthTokenService: RefreshAuthTokenServicing
    private let serverCredentialsStore: ServerCredentialsStoring
    private let serverSessionController: ServerSessionControlling
    private let serverAuthenticationController: ServerAuthenticationControlling

    // MARK: - Init

    public init(
        fileSystem: FileSysteming = FileSystem(),
        refreshAuthTokenService: RefreshAuthTokenServicing = RefreshAuthTokenService(),
        serverCredentialsStore: ServerCredentialsStoring = ServerCredentialsStore(),
        serverSessionController: ServerSessionControlling = ServerSessionController(),
        serverAuthenticationController: ServerAuthenticationControlling = ServerAuthenticationController()
    ) {
        self.fileSystem = fileSystem
        self.refreshAuthTokenService = refreshAuthTokenService
        self.serverCredentialsStore = serverCredentialsStore
        self.serverSessionController = serverSessionController
        self.serverAuthenticationController = serverAuthenticationController
    }

    public func refreshTokens(
        serverURL: URL
    ) async throws {
        guard let token = try await serverAuthenticationController.authenticationToken(serverURL: serverURL)
        else {
            throw ServerClientAuthenticationError.notAuthenticated
        }

        switch token {
        case let .user(legacyToken: _, accessToken: _, refreshToken: refreshToken):
            if let refreshToken {
                try await fetchTokens(serverURL: serverURL, refreshToken: refreshToken.token)
            }
        case .project:
            return
        }
    }

    private func fetchTokens(serverURL: URL, refreshToken: String) async throws {
        do {
            let newTokens = try await RetryProvider()
                .runWithRetries {
                    return try await refreshAuthTokenService.refreshTokens(
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
