import Foundation

/// A launch argument, passed when running a scheme.
public struct LaunchArgument: Equatable, Codable {
    // MARK: - Attributes

    /// Name of argument
    public var name: String
    /// If enabled then argument is marked as active
    public var isEnabled: Bool

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

extension [LaunchArgument] {
    init(launchArguments: [String: Bool]) {
        self = launchArguments.map(LaunchArgument.init)
            .sorted { $0.name < $1.name }
    }
}
