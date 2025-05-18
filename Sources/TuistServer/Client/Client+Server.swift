import Foundation
import OpenAPIRuntime
import OpenAPIURLSession

extension Client {
    private static let commonMiddlewares: [any ClientMiddleware] = [
        ServerClientRequestIdMiddleware(),
        ServerClientVerboseLoggingMiddleware(),
        ServerClientOutputWarningsMiddleware(),
    ]

    /// Tuist client for authenticated sessions
    public static func authenticated(serverURL: URL) -> Client {
        .init(
            serverURL: serverURL,
            transport: URLSessionTransport(configuration: .init(session: .tuistShared)),
            middlewares: commonMiddlewares + [
                ServerClientRequestIdMiddleware(),
                ServerClientCLIMetadataHeadersMiddleware(),
                ServerClientAuthenticationMiddleware(),
                ServerClientVerboseLoggingMiddleware(),
                ServerClientOutputWarningsMiddleware(),
            ]
        )
    }

    /// Tuist client for unauthenticated sessions
    public static func unauthenticated(serverURL: URL) -> Client {
        .init(
            serverURL: serverURL,
            transport: URLSessionTransport(configuration: .init(session: .tuistShared)),
            middlewares: commonMiddlewares
        )
    }
}
