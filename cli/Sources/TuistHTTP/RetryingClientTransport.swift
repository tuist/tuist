import Foundation
import HTTPTypes
import OpenAPIRuntime

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Retries transient transport-level failures (dropped connections, timeouts)
/// before surfacing them to the caller.
///
/// Intended for idempotent, content-addressed traffic such as CAS artifact
/// saves and lookups, where replaying a request is always safe. Under bursty
/// concurrency the connection pool races the server's keep-alive close and
/// URLSession surfaces "The network connection was lost"; a fresh attempt on a
/// new connection succeeds. Requests whose body cannot be re-iterated are
/// never retried.
public struct RetryingClientTransport: ClientTransport {
    private let base: any ClientTransport
    private let attempts: Int

    public init(
        wrapping base: any ClientTransport,
        attempts: Int = 3
    ) {
        self.base = base
        self.attempts = attempts
    }

    public func send(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var attempt = 0
        while true {
            attempt += 1
            do {
                return try await base.send(request, body: body, baseURL: baseURL, operationID: operationID)
            } catch {
                let bodyIsReplayable = body == nil || body?.iterationBehavior == .multiple
                guard attempt < attempts, bodyIsReplayable, isRetryable(error) else {
                    throw error
                }
                try await Task.sleep(nanoseconds: UInt64(attempt) * 200_000_000)
            }
        }
    }

    private func isRetryable(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .networkConnectionLost, .timedOut, .cannotConnectToHost:
            return true
        default:
            return false
        }
    }
}
