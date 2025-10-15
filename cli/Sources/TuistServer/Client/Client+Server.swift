import Foundation
import OpenAPIRuntime
import OpenAPIURLSession

extension Client {
    @TaskLocal public static var additionalMiddlewares: [any ClientMiddleware] = []

    /// Tuist client for authenticated sessions
    public static func authenticated(serverURL: URL) -> Client {
        .init(
            serverURL: serverURL,
            transport: URLSessionTransport(configuration: .init(session: .tuistShared)),
            middlewares: [
                ServerClientRequestIdMiddleware(),
                ServerClientCLIMetadataHeadersMiddleware(),
                ServerClientAuthenticationMiddleware(),
                ServerClientVerboseLoggingMiddleware(),
                ServerClientOutputWarningsMiddleware(),
            ] + additionalMiddlewares
        )
    }

    /// Tuist client for unauthenticated sessions
    public static func unauthenticated(serverURL: URL) -> Client {
        .init(
            serverURL: serverURL,
            transport: URLSessionTransport(configuration: .init(session: .tuistShared)),
            middlewares: [
                ServerClientRequestIdMiddleware(),
                ServerClientVerboseLoggingMiddleware(),
                ServerClientOutputWarningsMiddleware(),
            ]
        )
    }
}
