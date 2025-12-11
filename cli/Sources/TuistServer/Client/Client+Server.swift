import Foundation
import OpenAPIRuntime
import OpenAPIURLSession
import TuistHTTP

extension Client {
    @TaskLocal public static var additionalMiddlewares: [any ClientMiddleware] = []

    /// Tuist client for authenticated sessions
    public static func authenticated(serverURL: URL, authenticationURL: URL? = nil) -> Client {
        .init(
            serverURL: serverURL,
            transport: URLSessionTransport(configuration: .init(session: .tuistShared)),
            middlewares: [
                RequestIdMiddleware(),
                ServerClientCLIMetadataHeadersMiddleware(),
                ServerClientAuthenticationMiddleware(authenticationURL: authenticationURL),
                VerboseLoggingMiddleware(),
                OutputWarningsMiddleware(),
            ] + additionalMiddlewares
        )
    }

    /// Tuist client for unauthenticated sessions
    public static func unauthenticated(serverURL: URL) -> Client {
        .init(
            serverURL: serverURL,
            transport: URLSessionTransport(configuration: .init(session: .tuistShared)),
            middlewares: [
                RequestIdMiddleware(),
                VerboseLoggingMiddleware(),
                OutputWarningsMiddleware(),
            ]
        )
    }
}
