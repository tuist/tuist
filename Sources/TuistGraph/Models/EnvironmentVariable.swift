import Foundation

/// Represents an anvironment variable that is passed by when running a scheme
public struct EnvironmentVariable: Equatable, Codable, Hashable {
    // MARK: - Attributes

    /// Key of the environment variable
    public let key: String

    /// Value of the environment variable
    public let value: String

    /// If enabled then argument is marked as active
    public let isEnabled: Bool

    // MARK: - Init

    /// Create new environment variable
    /// - Parameters:
    ///     - key: Key of the environment variable
    ///     - value: Value of the environment variable
    ///     - isEnabled: If enabled then argument is marked as active
    public init(key: String, value: String, isEnabled: Bool) {
        self.key = key
        self.value = value
        self.isEnabled = isEnabled
    }
}
