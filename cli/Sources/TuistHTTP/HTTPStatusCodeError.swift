import Foundation

/// An error raised from a server response whose HTTP status code is known.
public protocol HTTPStatusCodeError: Error {
    var httpStatusCode: Int { get }

    /// Whether re-sending the request could produce a different outcome. Derived from the
    /// status code unless the response said otherwise.
    var isRetryable: Bool { get }
}

extension HTTPStatusCodeError {
    public var isRetryable: Bool {
        !HTTPRetryPolicy.isPermanentClientError(statusCode: httpStatusCode)
    }
}

/// The server rejected the request because the client is not authorized for it, and has
/// been sending enough such requests to be throttled. The throttling is a response to the
/// volume, not to congestion: waiting out `Retry-After` reaches the same denial.
public struct AuthorizationThrottledError: HTTPStatusCodeError, LocalizedError, Equatable {
    public let retryAfterSeconds: Int?

    public init(retryAfterSeconds: Int?) {
        self.retryAfterSeconds = retryAfterSeconds
    }

    public var httpStatusCode: Int { 429 }

    public var isRetryable: Bool { false }

    public var errorDescription: String? {
        "The server rejected too many unauthorized requests. Check that you have access to the project you are building against."
    }
}
