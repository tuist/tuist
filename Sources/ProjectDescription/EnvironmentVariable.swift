import Foundation

/// It represents an environment variable that is passed when running a scheme's action
public struct EnvironmentVariable: Equatable, Codable, Hashable, ExpressibleByStringLiteral {
    // MARK: - Attributes

    /// The value of the environment variable
    public var value: String
    /// Whether the variable is enabled or not
    public var isEnabled: Bool

    // MARK: - Init
    
    init(value: String, isEnabled: Bool) {
        self.value = value
        self.isEnabled = isEnabled
    }

    public static func environmentVariable(value: String, isEnabled: Bool) -> Self {
        self.init(value: value, isEnabled: isEnabled)
    }

    public init(stringLiteral value: String) {
        self.value = value
        isEnabled = true
    }
}
