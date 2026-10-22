import Foundation

/// Shared authentication error type for HTTP clients.
/// Used by both TuistServer and TuistCache to avoid duplication.
public enum ClientAuthenticationError: LocalizedError, Equatable {
    case notAuthenticated

    public var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be logged in to do this."
        }
    }
}

/// A failure to obtain credentials for a request, raised before the request is sent. Obtaining credentials retries on
/// its own, so `RetryMiddleware` does not replay the request again, which would multiply the refreshes it sends, and
/// rethrows `underlyingError` instead.
public struct CredentialAcquisitionError: Error {
    public let underlyingError: any Error

    public init(underlyingError: any Error) {
        self.underlyingError = underlyingError
    }
}
