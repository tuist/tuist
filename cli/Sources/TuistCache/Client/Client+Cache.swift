import Foundation
import OpenAPIRuntime
import TuistHTTP
import TuistServer
import TuistSupport

extension Client {
    /// Cache client for authenticated sessions
    /// - Parameters:
    ///   - cacheURL: The cache service URL
    ///   - authenticationURL: The main server URL for authentication (token refresh, validation)
    ///   - serverAuthenticationController: Controller for server authentication
    ///   - session: Optional URLSession override. The CAS path passes a
    ///     short-timeout session so a hung backend fails fast; other callers use
    ///     the shared session.
    public static func authenticated(
        cacheURL: URL,
        authenticationURL: URL,
        serverAuthenticationController: ServerAuthenticationControlling,
        session: URLSession? = nil
    ) -> Client {
        .init(
            serverURL: cacheURL,
            transport: TuistURLSessionTransport(session: session),
            middlewares: HARRecordingMiddlewareFactory.middlewares() + [
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
