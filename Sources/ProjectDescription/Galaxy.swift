import Foundation

// MARK: - Galaxy

public struct Galaxy: Codable, Equatable {
    /// The project token to authenticate with the API.
    public let token: String

    /// Initializes the Galaxy instance with its attributes.
    /// - Parameter token: The project token to authenticate with the API.
    public init(token: String) {
        self.token = token
        dumpIfNeeded(self)
    }
}
