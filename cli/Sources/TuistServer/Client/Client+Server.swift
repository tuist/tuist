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
                RetryMiddleware(),
                RequestIdMiddleware(),
                ServerClientFeatureFlagsHeadersMiddleware(),
                ServerClientCLIMetadataHeadersMiddleware(),
                ServerClientAuthenticationMiddleware(authenticationURL: authenticationURL),
                VerboseLoggingMiddleware(),
                OutputWarningsMiddleware(),
            ] + requestCompressionMiddlewares + additionalMiddlewares
        )
    }

    /// Innermost, so verbose logging still shows the uncompressed body.
    private static var requestCompressionMiddlewares: [any ClientMiddleware] {
        #if canImport(Darwin)
            [ServerClientRequestCompressionMiddleware()]
        #else
            []
        #endif
    }

    /// Tuist client for unauthenticated sessions
    public static func unauthenticated(serverURL: URL) -> Client {
        .init(
            serverURL: serverURL,
            transport: TuistURLSessionTransport(),
            middlewares: HARRecordingMiddlewareFactory.middlewares() + [
                RetryMiddleware(),
                RequestIdMiddleware(),
                ServerClientFeatureFlagsHeadersMiddleware(),
                VerboseLoggingMiddleware(),
                OutputWarningsMiddleware(),
            ]
        )
    }
}
