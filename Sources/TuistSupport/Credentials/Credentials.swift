import Foundation

public struct Credentials: Codable {
    /// Authentication token.
    let token: String

    /// Date when the token expires.
    let expiresAt: Date

    /// Initializes the credentials with its attributes.
    /// - Parameters:
    ///   - token: Authentication token.
    ///   - expiresAt: Date when the token expires
    init(token: String, expiresAt: Date) {
        self.token = token
        self.expiresAt = expiresAt
    }
}
