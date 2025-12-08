import Foundation
import HTTPTypes
import Mockable
import OpenAPIRuntime
import TuistSupport

/// Protocol for providing authentication tokens to the cache client.
/// This allows dependency injection of authentication without creating circular dependencies.
@Mockable
public protocol CacheAuthenticationProviding: Sendable {
    /// Returns an authentication token for the given server URL.
    /// - Parameter serverURL: The server URL to authenticate against.
    /// - Returns: The authentication token value, or nil if not authenticated.
    func authenticationToken(serverURL: URL) async throws -> String?
}

struct CacheClientAuthenticationMiddleware: ClientMiddleware {
    private let authenticationURL: URL
    private let authenticationProvider: CacheAuthenticationProviding

    init(authenticationURL: URL, authenticationProvider: CacheAuthenticationProviding) {
        self.authenticationURL = authenticationURL
        self.authenticationProvider = authenticationProvider
    }

    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID _: String,
        next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request

        guard let token = try await authenticationProvider.authenticationToken(serverURL: authenticationURL) else {
            throw ClientAuthenticationError.notAuthenticated
        }

        request.headerFields.append(
            .init(
                name: .authorization, value: "Bearer \(token)"
            )
        )

        return try await next(request, body, baseURL)
    }
}
