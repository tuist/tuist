import Foundation

public struct LaunchArgument: Equatable, Codable {
    // MARK: - Attributes

    public let name: String
    public let isEnabled: Bool

    // MARK: - Init

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
