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

/// A failure to obtain credentials for a request, raised before the request is sent. Obtaining credentials can
/// rotate a refresh token on the server, so `RetryMiddleware` replays the request only when `underlyingError`
/// shows the server was never reached, and otherwise rethrows `underlyingError`.
public struct CredentialAcquisitionError: Error {
    public let underlyingError: any Error

    public init(underlyingError: any Error) {
        self.underlyingError = underlyingError
    }
}
