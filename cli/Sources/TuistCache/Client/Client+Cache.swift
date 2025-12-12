import Foundation
import OpenAPIRuntime
import OpenAPIURLSession
import TuistHTTP
import TuistServer
import TuistSupport

extension Client {
    /// Cache client for authenticated sessions
    /// - Parameters:
    ///   - cacheURL: The cache service URL
    ///   - authenticationURL: The main server URL for authentication (token refresh, validation)
    ///   - serverAuthenticationController: Controller for server authentication
    public static func authenticated(
        cacheURL: URL,
        authenticationURL: URL,
        serverAuthenticationController: ServerAuthenticationControlling
    ) -> Client {
        .init(
            serverURL: cacheURL,
            transport: URLSessionTransport(configuration: .init(session: .tuistShared)),
            middlewares: [
                RequestIdMiddleware(),
                CacheClientAuthenticationMiddleware(
                    authenticationURL: authenticationURL,
                    serverAuthenticationController: serverAuthenticationController
                ),
                VerboseLoggingMiddleware(serviceName: "Tuist Cache"),
                OutputWarningsMiddleware(),
            ]
        )
    }
}
