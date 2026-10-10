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
    ///   - session: Optional URLSession override. A caller on a fail-fast path passes a
    ///     short-timeout session so a hung backend fails fast; every current caller uses
    ///     the shared session.
    ///   - retriesTransportErrors: Whether the retry middleware retries thrown transport
    ///     errors, including timeouts. Defaults to `true` so ordinary cache GETs retry
    ///     transient failures. A caller paired with a short-timeout session passes `false`
    ///     so a hung backend surfaces through that timeout instead of being replayed.
    ///     Retryable HTTP responses such as 503 keep retrying either way.
    ///   - fullHandle: The `account/project` the requests are for. Used to
    ///     narrow the cache token to that project, which matters for an
    ///     account-wide credential: without it the token carries every project
    ///     the credential reaches.
    public static func authenticated(
        cacheURL: URL,
        authenticationURL: URL,
        serverAuthenticationController: ServerAuthenticationControlling,
        session: URLSession? = nil,
        retriesTransportErrors: Bool = true,
        fullHandle: String? = nil
    ) -> Client {
        .init(
            serverURL: cacheURL,
            transport: TuistURLSessionTransport(session: session),
            middlewares: HARRecordingMiddlewareFactory.middlewares() + [
                RetryMiddleware(
                    retryableRequestMethods: ["GET"],
                    retriesTransportErrors: retriesTransportErrors,
                    retriesUnforwardedCacheRequests: true
                ),
                RequestIdMiddleware(),
                CacheClientAuthenticationMiddleware(
                    authenticationURL: authenticationURL,
                    serverAuthenticationController: serverAuthenticationController,
                    cacheTokenStore: CacheTokenStore.shared,
                    fullHandle: fullHandle
                ),
                VerboseLoggingMiddleware(serviceName: "Tuist Cache"),
                OutputWarningsMiddleware(),
            ]
        )
    }
}
