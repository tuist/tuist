import Foundation

/// It represents an argument that is passed when running a scheme's action
public struct LaunchArgument: Equatable, Codable {
    // MARK: - Attributes

    /// The name of the launch argument
    public let name: String
    /// Whether the argument is enabled or not
    public let isEnabled: Bool

    // MARK: - Init

    public init(name: String, isEnabled: Bool) {
        self.name = name
        self.isEnabled = isEnabled
    }
}
