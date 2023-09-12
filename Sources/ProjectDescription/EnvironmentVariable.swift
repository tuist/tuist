import Foundation

/// It represents an environment variable that is passed when running a scheme's action
public struct EnvironmentVariable: Equatable, Codable, Hashable, ExpressibleByStringLiteral {
    // MARK: - Attributes

    /// The value of the environment variable
    public let value: String
    /// Whether the variable is enabled or not
    public let isEnabled: Bool

    // MARK: - Init

    public init(value: String, isEnabled: Bool) {
        self.value = value
        self.isEnabled = isEnabled
    }

    public init(stringLiteral value: String) {
        self.value = value
        isEnabled = true
    }
}
