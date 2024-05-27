import Foundation
import OpenAPIRuntime
import OpenAPIURLSession

extension Client {
    private static let commonMiddlewares: [any ClientMiddleware] = [
        CloudClientRequestIdMiddleware(),
        CloudClientVerboseLoggingMiddleware(),
        CloudClientOutputWarningsMiddleware(),
    ]

    /// Tuist Cloud client for authenticated sessions
    static func cloud(serverURL: URL) -> Client {
        .init(
            serverURL: serverURL,
            transport: URLSessionTransport(configuration: .init(session: .sharedCloud)),
            middlewares: commonMiddlewares + [
                CloudClientRequestIdMiddleware(),
                CloudClientCLIMetadataHeadersMiddleware(),
                CloudClientAuthenticationMiddleware(),
                CloudClientVerboseLoggingMiddleware(),
                CloudClientOutputWarningsMiddleware(),
            ]
        )
    }

    /// Tuist Cloud client for unauthenticated sessions
    static func unauthenticatedCloud(serverURL: URL) -> Client {
        .init(
            serverURL: serverURL,
            transport: URLSessionTransport(configuration: .init(session: .sharedCloud)),
            middlewares: commonMiddlewares
        )
    }
}
