import Foundation

public struct Credentials: Codable {
    /// Authentication token.
    let token: String

    /// Account identifier
    let account: String

    /// Initializes the credentials with its attributes.
    /// - Parameters:
    ///   - token: Authentication token.
    ///   - username: Account identifier.
    init(token: String, account: String) {
        self.token = token
        self.account = account
    }
}
