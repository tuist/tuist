import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
import TuistHTTP
import TuistThreadSafe

/// Sends idempotent requests that bypass the server client, such as transfers to and from presigned storage URLs, and
/// sends them again after a transport error or a 408, 429 or 5xx response, reading the body again on every attempt.
/// Any other response is returned as soon as it arrives, and once the retries run out the last response is returned,
/// so the caller reports a failed transfer as it would a single attempt.
public struct RetryingURLTransfer {
    private let urlSession: URLSession
    private let retryProvider: RetryProviding

    public init(urlSession: URLSession, retryProvider: RetryProviding = RetryProvider()) {
        self.urlSession = urlSession
        self.retryProvider = retryProvider
    }

    /// Downloads to a temporary file the caller owns. The files of superseded attempts are removed.
    public func download(_ request: URLRequest) async throws -> (URL, URLResponse) {
        try await send(
            discard: { try? FileManager.default.removeItem(at: $0) },
            attempt: { [urlSession] in try await urlSession.download(for: request) }
        )
    }

    public func upload(_ request: URLRequest, fromFile file: URL) async throws -> (Data, URLResponse) {
        try await send(attempt: { [urlSession] in try await urlSession.upload(for: request, fromFile: file) })
    }

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await send(attempt: { [urlSession] in try await urlSession.data(for: request) })
    }

    private func send<T: Sendable>(
        discard: @escaping @Sendable (T) -> Void = { _ in },
        attempt: @escaping @Sendable () async throws -> (T, URLResponse)
    ) async throws -> (T, URLResponse) {
        let lastRetryableResult = ThreadSafe<(T, URLResponse)?>(nil)
        do {
            let result = try await retryProvider.runWithRetries {
                let result = try await attempt()
                guard let statusCode = (result.1 as? HTTPURLResponse)?.statusCode,
                      statusCode == 408 || statusCode == 429 || (500 ..< 600).contains(statusCode)
                else { return result }
                lastRetryableResult.mutate { previous in
                    previous.map { discard($0.0) }
                    previous = result
                }
                throw RetryableTransferStatusError(httpStatusCode: statusCode)
            }
            lastRetryableResult.value.map { discard($0.0) }
            return result
        } catch let error as RetryableTransferStatusError {
            guard let result = lastRetryableResult.value else { throw error }
            return result
        } catch {
            lastRetryableResult.value.map { discard($0.0) }
            throw error
        }
    }
}

private struct RetryableTransferStatusError: HTTPStatusCodeError {
    let httpStatusCode: Int
}
