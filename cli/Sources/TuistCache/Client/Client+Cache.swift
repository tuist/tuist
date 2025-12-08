import Foundation
import OpenAPIRuntime
import OpenAPIURLSession
import TuistSupport

extension Client {
    /// Cache client for authenticated sessions
    /// - Parameters:
    ///   - cacheURL: The cache service URL
    ///   - authenticationURL: The main server URL for authentication (token refresh, validation)
    ///   - authenticationProvider: Provider for authentication tokens
    public static func authenticated(
        cacheURL: URL,
        authenticationURL: URL,
        authenticationProvider: CacheAuthenticationProviding
    ) -> Client {
        .init(
            serverURL: cacheURL,
            transport: URLSessionTransport(configuration: .init(session: .tuistShared)),
            middlewares: [
                RequestIdMiddleware(),
                CacheClientAuthenticationMiddleware(
                    authenticationURL: authenticationURL,
                    authenticationProvider: authenticationProvider
                ),
                VerboseLoggingMiddleware(serviceName: "Tuist Cache"),
                OutputWarningsMiddleware(),
            ]
        )
    }
}
