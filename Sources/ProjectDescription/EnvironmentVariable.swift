import Foundation

public struct EnvironmentVariable: Equatable, Codable {
    public let key: String
    public let value: String
    public let isEnabled: Bool

    // MARK: - Init

    /// Create new launch argument
    /// - Parameters:
    ///     - name: Name of argument
    ///     - isEnabled: If enabled then argument is marked as active
    public init(key: String, value: String, isEnabled: Bool) {
        self.key = key
        self.value = value
        self.isEnabled = isEnabled
    }
}
