import Foundation
import HTTPTypes
import OpenAPIRuntime
#if canImport(TuistSupport)
    import TuistSupport
#endif

public enum ServerClientAuthenticationError: LocalizedError, Equatable {
    case notAuthenticated

    public var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be logged in to do this. To log in, run 'tuist auth login'."
        }
    }
}

/// Injects an authorization header to every request.
struct ServerClientAuthenticationMiddleware: ClientMiddleware {
    private let serverAuthenticationController: ServerAuthenticationControlling
    private let serverCredentialsStore: ServerCredentialsStoring
    private let refreshAuthTokenService: RefreshAuthTokenServicing
    private let cachedValueStore: CachedValueStoring

    init() {
        self.init(
            serverAuthenticationController: ServerAuthenticationController(),
            serverCredentialsStore: ServerCredentialsStore(),
            refreshAuthTokenService: RefreshAuthTokenService(),
            cachedValueStore: CachedValueStore.shared
        )
    }

    init(
        serverAuthenticationController: ServerAuthenticationControlling,
        serverCredentialsStore: ServerCredentialsStoring,
        refreshAuthTokenService: RefreshAuthTokenServicing,
        cachedValueStore: CachedValueStoring,
    ) {
        self.serverAuthenticationController = serverAuthenticationController
        self.serverCredentialsStore = serverCredentialsStore
        self.refreshAuthTokenService = refreshAuthTokenService
        self.cachedValueStore = cachedValueStore
    }

    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID _: String,
        next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request

        guard let token = try await serverAuthenticationController.authenticationToken(serverURL: baseURL)
        else {
            throw ServerClientAuthenticationError.notAuthenticated
        }

        let tokenValue: String
        switch token {
        case let .project(token):
            tokenValue = token
        case let .user(legacyToken: legacyToken, accessToken: accessToken, refreshToken: refreshToken):
            if let legacyToken {
                tokenValue = legacyToken
            } else if let accessToken {
                // We consider a token to be expired if the expiration date is in the past or 30 seconds from now
                let isExpired = accessToken.expiryDate
                    .timeIntervalSince(Date.now()) < 30

                if isExpired {
                    guard let refreshToken else { throw ServerClientAuthenticationError.notAuthenticated }
                    tokenValue = try await cachedValueStore.getValue(key: refreshToken.token) {
                        try await refreshTokens(baseURL: baseURL, refreshToken: refreshToken)
                    }
                    .accessToken
                } else {
                    tokenValue = accessToken.token
                }
            } else {
                throw ServerClientAuthenticationError.notAuthenticated
            }
        }

        request.headerFields.append(.init(
            name: .authorization, value: "Bearer \(tokenValue)"
        ))
        return try await next(request, body, baseURL)
    }

    private func refreshTokens(
        baseURL: URL,
        refreshToken: JWT
    ) async throws -> ServerAuthenticationTokens {
        do {
            let newTokens = try await RetryProvider()
                .runWithRetries {
                    return try await refreshAuthTokenService.refreshTokens(
                        serverURL: baseURL,
                        refreshToken: refreshToken.token
                    )
                }
            try await serverCredentialsStore
                .store(
                    credentials: ServerCredentials(
                        token: nil,
                        accessToken: newTokens.accessToken,
                        refreshToken: newTokens.refreshToken
                    ),
                    serverURL: baseURL
                )
            return newTokens
        } catch {
            throw ServerClientAuthenticationError.notAuthenticated
        }
    }
}
