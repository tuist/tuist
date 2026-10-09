import Foundation
import TuistAppStorage

public struct Account: Equatable, Codable {
    public let email: String
    public let handle: String

    public init(email: String, handle: String) {
        self.email = email
        self.handle = handle
    }
}

public enum AuthenticationState: Equatable {
    /// `server` is the self-hosted server the session belongs to, or `nil` for Tuist-hosted.
    case loggedIn(account: Account, server: AppServerConfiguration? = nil)
    case loggedOut
}

/// Tuist-hosted sessions keep the format older app versions read. Self-hosted sessions use a key
/// those versions don't recognize, so after a downgrade they fall back to logged out instead of
/// treating the session as Tuist-hosted.
extension AuthenticationState: Codable {
    private enum CodingKeys: String, CodingKey {
        case loggedIn
        case loggedInSelfHosted
        case loggedOut
    }

    private struct Session: Codable {
        let account: Account
        let server: AppServerConfiguration?
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let session = try container.decodeIfPresent(Session.self, forKey: .loggedInSelfHosted) {
            self = .loggedIn(account: session.account, server: session.server)
        } else if let session = try container.decodeIfPresent(Session.self, forKey: .loggedIn) {
            self = .loggedIn(account: session.account)
        } else if container.contains(.loggedOut) {
            self = .loggedOut
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unknown authentication state")
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .loggedIn(account, nil):
            try container.encode(Session(account: account, server: nil), forKey: .loggedIn)
        case let .loggedIn(account, server):
            try container.encode(Session(account: account, server: server), forKey: .loggedInSelfHosted)
        case .loggedOut:
            try container.encode([String: String](), forKey: .loggedOut)
        }
    }
}

public struct AuthenticationStateKey: AppStorageKey {
    public static let key = "authenticationState"
    public static let defaultValue: AuthenticationState = .loggedOut
}
