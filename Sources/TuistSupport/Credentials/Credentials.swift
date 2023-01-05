import Foundation

public struct Credentials: Codable, Equatable {
    /// Authentication token.
    public let token: String

    /// Account identifier
    public let account: String

    /// Initializes the credentials with its attributes.
    /// - Parameters:
    ///   - token: Authentication token.
    ///   - account: Account identifier.
    public init(token: String, account: String) {
        self.token = token
        self.account = account
    }
}
