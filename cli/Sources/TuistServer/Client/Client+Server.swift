import Foundation
import OpenAPIRuntime
import TuistHTTP

extension Client {
    @TaskLocal public static var additionalMiddlewares: [any ClientMiddleware] = []

    /// Tuist client for authenticated sessions
    public static func authenticated(serverURL: URL, authenticationURL: URL? = nil) -> Client {
        .init(
            serverURL: serverURL,
            transport: TuistURLSessionTransport(),
            middlewares: HARRecordingMiddlewareFactory.middlewares() + [
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
            transport: TuistURLSessionTransport(),
            middlewares: HARRecordingMiddlewareFactory.middlewares() + [
                RequestIdMiddleware(),
                VerboseLoggingMiddleware(),
                OutputWarningsMiddleware(),
            ]
        )
    }
}
