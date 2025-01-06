import Foundation
import HTTPTypes
import OpenAPIRuntime
import TuistSupport

public enum ServerClientAuthenticationError: FatalError, Equatable {
    case notAuthenticated

    public var type: ErrorType {
        switch self {
        case .notAuthenticated:
            return .abort
        }
    }

    public var description: String {
        switch self {
        case .notAuthenticated:
            return "You must be logged in to do this."
        }
    }
}

/// Injects an authorization header to every request.
struct ServerClientAuthenticationMiddleware: ClientMiddleware {
    private let serverAuthenticationController: ServerAuthenticationControlling
    private let serverCredentialsStore: ServerCredentialsStoring
    private let refreshAuthTokenService: RefreshAuthTokenServicing
    private let dateService: DateServicing
    private let cachedValueStore: CachedValueStoring
    private let envVariables: [String: String]

    init() {
        self.init(
            serverAuthenticationController: ServerAuthenticationController(),
            serverCredentialsStore: ServerCredentialsStore(),
            refreshAuthTokenService: RefreshAuthTokenService(),
            dateService: DateService(),
            cachedValueStore: CachedValueStore.shared,
            envVariables: ProcessInfo.processInfo.environment
        )
    }

    init(
        serverAuthenticationController: ServerAuthenticationControlling,
        serverCredentialsStore: ServerCredentialsStoring,
        refreshAuthTokenService: RefreshAuthTokenServicing,
        dateService: DateServicing,
        cachedValueStore: CachedValueStoring,
        envVariables: [String: String]
    ) {
        self.serverAuthenticationController = serverAuthenticationController
        self.serverCredentialsStore = serverCredentialsStore
        self.refreshAuthTokenService = refreshAuthTokenService
        self.dateService = dateService
        self.cachedValueStore = cachedValueStore
        self.envVariables = envVariables
    }

    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID _: String,
        next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request

        /// Cirrus environments don't require authentication so we skip in these cases
        if envVariables[Constants.EnvironmentVariables.cirrusTuistCacheURL] != nil {
            return try await next(request, body, baseURL)
        }

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
            } else if let accessToken, let refreshToken {
                // We consider a token to be expired if the expiration date is in the past or 30 seconds from now
                let isExpired = accessToken.expiryDate
                    .timeIntervalSince(dateService.now()) < 30

                if isExpired {
                    tokenValue = try await cachedValueStore.getValue(key: refreshToken.token) {
                        try await refreshAuthTokenService.refreshTokens(serverURL: baseURL, refreshToken: refreshToken.token)
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
}
