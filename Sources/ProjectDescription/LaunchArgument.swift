import Foundation

/// Represents launch argument that is passed by when running a scheme
public struct LaunchArgument: Equatable, Codable {
    // MARK: - Attributes

    /// Name of argument
    public let name: String
    /// If enabled then argument is marked as active
    public let isEnabled: Bool

    // MARK: - Init

    /// Create new launch argument
    /// - Parameters:
    ///     - name: Name of argument
    ///     - isEnabled: If enabled then argument is marked as active
    public init(name: String, isEnabled: Bool) {
        self.name = name
        self.isEnabled = isEnabled
    }
}

internal extension Array where Element == LaunchArgument {
    init(launchArguments: [String: Bool]) {
        self = launchArguments.map(LaunchArgument.init)
            .sorted { $0.name < $1.name }
    }
}
