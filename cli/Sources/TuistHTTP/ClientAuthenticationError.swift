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
